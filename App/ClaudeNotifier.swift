import Combine
import Foundation
import UserNotifications

/// Lets you know when Claude finishes something that took a while, so you can look away.
@MainActor
final class ClaudeNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let enabledKey = "notifyWhenClaudeFinishes"
    /// Quick answers do not need a ping.
    static let minimumDuration: TimeInterval = 20

    private let launchedAt = Date()
    private var lastNotified = Date.distantPast
    private var subscriptions: Set<AnyCancellable> = []

    init(watcher: ClaudeActivityWatcher) {
        super.init()
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        UNUserNotificationCenter.current().delegate = self

        watcher.$lastFinishedTurn
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] turn in self?.notify(turn) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.askPermissionIfNeeded() }
            .store(in: &subscriptions)
        askPermissionIfNeeded()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    private func askPermissionIfNeeded() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ turn: FinishedTurn) {
        guard isEnabled,
              turn.date > launchedAt, turn.date > lastNotified,
              Date().timeIntervalSince(turn.date) < 120 else { return }
        if let duration = turn.duration, duration < Self.minimumDuration { return }
        lastNotified = turn.date

        let content = UNMutableNotificationContent()
        content.title = "Claude finished"
        content.body = Format.finished(turn)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "claude-finished-\(Int(turn.date.timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
