import AppKit
import Combine

/// Decides what Clawd should be doing, from Claude's activity first and then from what
/// you are doing on the Mac. Only the app in front and how long ago a key was pressed are
/// checked. Which keys were pressed is never known.
@MainActor
final class ActivityTracker: ObservableObject {
    @Published private(set) var activity: PetActivity = .idle

    var limitReached = false {
        didSet { if oldValue != limitReached { evaluate() } }
    }

    private enum Source {
        case claude, user
    }

    private let watcher: ClaudeActivityWatcher
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var pending: (activity: PetActivity, since: Date)?
    private var shownAt = Date.distantPast
    private var categories: [String: PetActivity] = [:]
    private lazy var browsers: Set<String> = Self.installedBrowsers()

    init(watcher: ClaudeActivityWatcher) {
        self.watcher = watcher
    }

    func start() {
        subscription = watcher.$latest
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.evaluate() }
                self?.evaluate()
            }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer?.tolerance = 0.3
        evaluate()
    }

    func stop() {
        subscription = nil
        timer?.invalidate()
        timer = nil
    }

    private func evaluate() {
        let now = Date()
        let (wanted, source) = desiredActivity(at: now)
        guard wanted != activity else {
            pending = nil
            return
        }
        if pending?.activity != wanted {
            pending = (wanted, now)
        }

        // Claude changes tools quickly and those should show right away. Things you do
        // have to settle for a moment, and every pose stays up for a few seconds.
        let settle: TimeInterval = source == .claude ? 0.5 : 1.5
        let minimum: TimeInterval = activity == .sleeping || wanted == .celebrating ? 0 : 3
        guard let pending, now.timeIntervalSince(pending.since) >= settle,
              now.timeIntervalSince(shownAt) >= minimum else { return }

        activity = wanted
        shownAt = now
        self.pending = nil
    }

    private func desiredActivity(at now: Date) -> (PetActivity, Source) {
        if limitReached { return (.sleeping, .claude) }

        if let event = watcher.latest {
            let age = now.timeIntervalSince(event.date)
            switch event.activity {
            case .celebrating where age < 6:
                return (.celebrating, .claude)
            case .building where age < 150,
                 .typing where age < 60,
                 .reading where age < 60,
                 .searching where age < 90,
                 .thinking where age < 60:
                return (event.activity, .claude)
            default:
                break
            }
        }

        let anyInput = CGEventType(rawValue: ~0) ?? .mouseMoved
        if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) > 5 * 60 {
            return (.sleeping, .user)
        }
        if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 2.5 {
            return (.typing, .user)
        }
        if let app = NSWorkspace.shared.frontmostApplication, let activity = category(of: app) {
            return (activity, .user)
        }
        return (.idle, .user)
    }

    // MARK: Apps

    private func category(of app: NSRunningApplication) -> PetActivity? {
        guard let identifier = app.bundleIdentifier else { return nil }
        if let cached = categories[identifier] { return cached == .idle ? nil : cached }

        var result = PetActivity.idle
        if browsers.contains(identifier) {
            result = .searching
        } else if Self.readers.contains(where: identifier.hasPrefix) {
            result = .reading
        } else if Self.developerTools.contains(where: identifier.hasPrefix) {
            result = .building
        } else if let url = app.bundleURL,
                  let type = Bundle(url: url)?.infoDictionary?["LSApplicationCategoryType"] as? String {
            if type.hasSuffix("developer-tools") {
                result = .building
            } else if ["books", "news", "reference", "education"].contains(where: type.hasSuffix) {
                result = .reading
            }
        }
        categories[identifier] = result
        return result == .idle ? nil : result
    }

    private static func installedBrowsers() -> Set<String> {
        guard let probe = URL(string: "https://example.com") else { return [] }
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: probe)
        return Set(apps.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }

    private static let readers = [
        "com.apple.Preview", "com.apple.iBooksX", "com.amazon.Kindle", "com.adobe.Reader",
        "com.adobe.Acrobat", "net.sourceforge.skim-app", "com.readdle.PDFExpert", "com.apple.news",
        "com.reederapp", "com.ranchero.NetNewsWire",
    ]

    private static let developerTools = [
        "com.apple.dt.Xcode", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp",
        "com.mitchellh.ghostty", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "dev.zed.Zed", "com.jetbrains", "com.sublimetext", "com.panic.Nova", "com.exafunction.windsurf",
    ]
}
