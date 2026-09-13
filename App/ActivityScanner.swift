import Foundation

/// Adds up tokens from the session logs Claude Code keeps in ~/.claude/projects.
/// Files are read incrementally, so a refresh only parses lines written since the last one.
actor ActivityScanner {
    private struct Record {
        var date: Date
        var tokens: Int
    }

    private var offsets: [String: UInt64] = [:]
    private var records: [String: Record] = [:]
    private var lastActiveAt: Date?

    private let root = URL(fileURLWithPath: SnapshotStore.realHomeDirectory)
        .appendingPathComponent(".claude/projects", isDirectory: true)

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let tokenFields = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]

    func scan(now: Date = Date()) -> Activity? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -6, to: today),
              let files = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else { return nil }

        var foundLogs = false
        for case let url as URL in files where url.pathExtension == "jsonl" {
            foundLogs = true
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate, modified >= windowStart else { continue }

            let size = UInt64(values.fileSize ?? 0)
            var offset = offsets[url.path] ?? 0
            if size < offset { offset = 0 }
            guard size > offset else { continue }
            offsets[url.path] = read(url, from: offset, windowStart: windowStart)
        }

        records = records.filter { $0.value.date >= windowStart }
        guard foundLogs else { return nil }

        var days = (0..<7).map { index in
            Activity.Day(date: calendar.date(byAdding: .day, value: index, to: windowStart) ?? windowStart, tokens: 0, messages: 0)
        }
        for record in records.values {
            let index = calendar.dateComponents([.day], from: windowStart, to: calendar.startOfDay(for: record.date)).day ?? -1
            guard days.indices.contains(index) else { continue }
            days[index].tokens += record.tokens
            days[index].messages += 1
        }
        return Activity(days: days, lastActiveAt: lastActiveAt)
    }

    private func read(_ url: URL, from offset: UInt64, windowStart: Date) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }

        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(),
              let lastNewline = data.lastIndex(of: 0x0A) else { return offset }

        // Stop at the last full line, the one after it may still be getting written.
        let complete = data[data.startIndex...lastNewline]
        for line in complete.split(separator: 0x0A) where line.range(of: Self.usageMarker) != nil {
            ingest(line, windowStart: windowStart)
        }
        return offset + UInt64(complete.count)
    }

    private func ingest(_ line: Data, windowStart: Date) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let timestamp = (object["timestamp"] as? String).flatMap(ClaudeAPI.parseDate) else { return }

        if timestamp > (lastActiveAt ?? .distantPast) {
            lastActiveAt = timestamp
        }
        guard timestamp >= windowStart else { return }

        // Streaming writes the same reply more than once, and resumed sessions copy
        // history into new files, so count each request once.
        let messageID = message["id"] as? String ?? UUID().uuidString
        let requestID = object["requestId"] as? String ?? ""
        let tokens = Self.tokenFields.reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
        records[messageID + requestID] = Record(date: timestamp, tokens: tokens)
    }
}
