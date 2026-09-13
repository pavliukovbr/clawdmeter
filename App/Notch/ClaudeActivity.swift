import CoreServices
import Foundation

enum PetActivity: String, CaseIterable {
    case idle, thinking, typing, reading, searching, building, celebrating, sleeping
}

enum ToolActivity {
    static func activity(forTool name: String) -> PetActivity {
        let tool = name.lowercased()
        if ["web", "search", "fetch", "browser", "chrome", "navigate"].contains(where: tool.contains) {
            return .searching
        }
        if ["read", "grep", "glob", "ls"].contains(tool) || tool.contains("read") {
            return .reading
        }
        if ["edit", "multiedit", "write", "notebookedit", "todowrite"].contains(tool) || tool.contains("write") || tool.contains("edit") {
            return .typing
        }
        return .building
    }
}

/// Watches the Claude Code session logs to tell what Claude is doing right now.
/// Only tool names and timestamps are looked at. Nothing is stored or sent anywhere.
final class ClaudeActivityWatcher: ObservableObject {
    struct Event: Equatable {
        var activity: PetActivity
        var date: Date
        /// A tool was called and its result has not been written yet, like a long build
        /// or a permission prompt.
        var waitingOnTool: Bool
    }

    @Published private(set) var latest: Event?
    @Published private(set) var lastFinishedTurn: FinishedTurn?
    /// The last hidden surprise a prompt asked for.
    @Published private(set) var easterEgg: EasterEgg?

    struct EasterEgg: Equatable {
        enum Kind {
            case webSlinger, popStar
        }

        var kind: Kind
        var date: Date
    }

    private let root = URL(fileURLWithPath: SnapshotStore.realHomeDirectory)
        .appendingPathComponent(".claude/projects", isDirectory: true)
    private let queue = DispatchQueue(label: "clawdmeter.claude-activity", qos: .utility)
    private var stream: FSEventStreamRef?

    /// True while Claude is in the middle of a task, or has been in the last `window` seconds.
    func isClaudeWorking(within window: TimeInterval, now: Date = Date()) -> Bool {
        guard let latest else { return false }
        let age = now.timeIntervalSince(latest.date)
        if latest.waitingOnTool { return age < 3 * 3600 }
        return age < window
    }

    func start() {
        guard stream == nil else { return }
        queue.async { [weak self] in self?.scanRecentLogs() }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ClaudeActivityWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.handle(changed)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: Reading logs

    private func handle(_ paths: [String]) {
        for path in Set(paths) where path.hasSuffix(".jsonl") {
            if let tail = Self.readTail(of: URL(fileURLWithPath: path)) {
                publish(tail)
            }
        }
    }

    private func scanRecentLogs() {
        guard let files = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var newest: (url: URL, date: Date)?
        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  Date().timeIntervalSince(date) < 3 * 3600 else { continue }
            if date > newest?.date ?? .distantPast {
                newest = (url, date)
            }
        }
        if let newest, let tail = Self.readTail(of: newest.url) {
            publish(tail)
        }
    }

    private func publish(_ tail: LogTail) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let turn = tail.finishedTurn, turn.date > self.lastFinishedTurn?.date ?? .distantPast {
                self.lastFinishedTurn = turn
            }
            if let egg = tail.easterEgg, egg.date > self.easterEgg?.date ?? .distantPast {
                self.easterEgg = egg
            }
            if let latest = self.latest, latest.date > tail.event.date { return }
            self.latest = tail.event
        }
    }

    struct LogTail {
        var event: Event
        var finishedTurn: FinishedTurn?
        var easterEgg: EasterEgg?
    }

    /// Reads the end of a session log. When the last step finished a turn, it also looks back
    /// for the prompt that started it, to know how long Claude worked.
    static func readTail(of url: URL) -> LogTail? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 256_000 ? size - 256_000 : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }

        var lines = data.split(separator: 0x0A)
        if start > 0, !lines.isEmpty { lines.removeFirst() }

        // Only look further back when it matters: to time a finished turn, or to catch the
        // prompt that was just sent.
        var latest: Line?
        var prompt: Line?
        var looked = 0
        for line in lines.reversed() {
            guard let parsed = parse(line) else { continue }
            looked += 1
            if latest == nil { latest = parsed }
            if parsed.isPrompt {
                prompt = parsed
                break
            }
            if latest?.event.activity != .celebrating, looked >= 6 { break }
        }
        guard let latest else { return nil }

        var turn: FinishedTurn?
        if latest.event.activity == .celebrating {
            turn = FinishedTurn(
                date: latest.event.date,
                duration: prompt.map { latest.event.date.timeIntervalSince($0.event.date) },
                project: latest.project
            )
        }
        let egg = prompt.flatMap { line in line.easterEgg.map { EasterEgg(kind: $0, date: line.event.date) } }
        return LogTail(event: latest.event, finishedTurn: turn, easterEgg: egg)
    }

    private struct Line {
        var event: Event
        var isPrompt: Bool
        var project: String?
        var easterEgg: EasterEgg.Kind?
    }

    /// The only things ever looked for in a prompt. Nothing from it is kept.
    private static func easterEgg(in text: String) -> EasterEgg.Kind? {
        let squashed = text.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        if squashed.contains("spiderman") || squashed.contains("homemaranha") { return .webSlinger }
        if squashed.contains("ladygaga") { return .popStar }
        return nil
    }

    private static func parse(_ line: Data) -> Line? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String, type == "assistant" || type == "user",
              object["isMeta"] as? Bool != true,
              let message = object["message"] as? [String: Any],
              let date = (object["timestamp"] as? String).flatMap(ClaudeAPI.parseDate) else { return nil }

        let project = (object["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        let blocks = message["content"] as? [[String: Any]] ?? []

        if type == "assistant" {
            if let tool = blocks.last(where: { $0["type"] as? String == "tool_use" }),
               let name = tool["name"] as? String {
                return Line(event: Event(activity: ToolActivity.activity(forTool: name), date: date, waitingOnTool: true), isPrompt: false, project: project)
            }
            let finished = message["stop_reason"] as? String == "end_turn"
            return Line(event: Event(activity: finished ? .celebrating : .thinking, date: date, waitingOnTool: false), isPrompt: false, project: project)
        }

        // A prompt or a tool result: Claude is about to think about it.
        let isToolResult = blocks.contains { $0["type"] as? String == "tool_result" }
        let text = (message["content"] as? String) ?? blocks.compactMap { $0["text"] as? String }.joined()
        if text.contains("<local-command") || text.contains("<command-name>") { return nil }
        if text.contains("[Request interrupted") {
            return Line(event: Event(activity: .idle, date: date, waitingOnTool: false), isPrompt: true, project: project)
        }
        return Line(
            event: Event(activity: .thinking, date: date, waitingOnTool: false),
            isPrompt: !isToolResult,
            project: project,
            easterEgg: isToolResult ? nil : easterEgg(in: text)
        )
    }
}
