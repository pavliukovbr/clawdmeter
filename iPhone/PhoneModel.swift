import ActivityKit
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

@MainActor
final class PhoneModel: ObservableObject {
    enum Connection: Equatable {
        case notPaired
        case connecting
        case connected
        case unreachable
        case rejected
    }

    @Published private(set) var pairing: PhonePairing?
    @Published private(set) var stored: PhoneVault.StoredReply?
    @Published private(set) var connection: Connection
    @Published var pairingFailed = false
    @Published var finishedBanner: FinishedTurn?
    @Published var showsInDynamicIsland: Bool {
        didSet {
            UserDefaults.standard.set(showsInDynamicIsland, forKey: "showsInDynamicIsland")
            Task { await updateLiveActivity() }
        }
    }

    private var timer: Timer?

    init() {
        let pairing = PhoneVault.pairing
        self.pairing = pairing
        stored = PhoneVault.lastReply
        connection = pairing == nil ? .notPaired : .connecting
        showsInDynamicIsland = UserDefaults.standard.bool(forKey: "showsInDynamicIsland")

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard UIApplication.shared.applicationState == .active else { return }
                await self?.refresh()
            }
        }
    }

    var snapshot: UsageSnapshot? { stored?.reply.snapshot }

    func pair(with url: URL) {
        guard let pairing = PhonePairing(url: url) else {
            pairingFailed = true
            return
        }
        PhoneVault.pairing = pairing
        PhoneVault.lastReply = nil
        self.pairing = pairing
        stored = nil
        connection = .connecting
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        Task { await refresh() }
    }

    func pasteLink() {
        let text = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? ""
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            pairingFailed = true
            return
        }
        pair(with: url)
    }

    func unpair() {
        PhoneVault.pairing = nil
        PhoneVault.lastReply = nil
        pairing = nil
        stored = nil
        connection = .notPaired
        showsInDynamicIsland = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh() async {
        guard pairing != nil else {
            connection = .notPaired
            return
        }
        let result = await UsageRefresher.refresh()
        stored = result.stored
        pairing = PhoneVault.pairing
        if result.error == nil {
            announce(result.stored?.reply.lastFinishedTurn)
        }
        switch result.error {
        case nil: connection = .connected
        case .rejected?: connection = .rejected
        case .notPaired?: connection = .notPaired
        case .unreachable?: connection = .unreachable
        }
        WidgetCenter.shared.reloadAllTimelines()
        await updateLiveActivity()
    }

    // MARK: Claude finished

    /// Shows a banner when Claude finished something that took a while since the last check.
    /// With the app in the background it posts a notification instead, whenever iOS lets it run.
    private func announce(_ turn: FinishedTurn?) {
        guard let turn else { return }
        let key = "lastAnnouncedTurn"
        let previous = UserDefaults.standard.object(forKey: key) as? Date
        guard turn.date > previous ?? .distantPast else { return }
        UserDefaults.standard.set(turn.date, forKey: key)
        guard previous != nil, Date().timeIntervalSince(turn.date) < 30 * 60 else { return }
        if let duration = turn.duration, duration < 20 { return }

        if UIApplication.shared.applicationState == .active {
            withAnimation(.spring(duration: 0.5)) { finishedBanner = turn }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard self?.finishedBanner == turn else { return }
                withAnimation(.easeOut(duration: 0.3)) { self?.finishedBanner = nil }
            }
        } else {
            let content = UNMutableNotificationContent()
            content.title = "Claude finished"
            content.body = Format.finished(turn)
            content.sound = .default
            let request = UNNotificationRequest(identifier: "claude-finished-\(Int(turn.date.timeIntervalSince1970))", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: Dynamic Island

    private func updateLiveActivity() async {
        let running = ActivityKit.Activity<UsageActivityAttributes>.activities
        guard showsInDynamicIsland, let snapshot else {
            for activity in running {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let content = ActivityContent(
            state: UsageActivityAttributes.ContentState(snapshot: snapshot),
            staleDate: Date().addingTimeInterval(30 * 60)
        )
        if let activity = running.first {
            await activity.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? ActivityKit.Activity<UsageActivityAttributes>.request(
                attributes: UsageActivityAttributes(macName: pairing?.name ?? "Mac"),
                content: content,
                pushType: nil
            )
        }
    }
}
