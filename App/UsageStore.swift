import AppKit
import Combine
import WidgetKit

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false

    private let scanner = ActivityScanner()
    private var cachedPlan: (plan: Plan, fetchedAt: Date)?
    private var timer: Timer?
    private var lastRefresh = Date.distantPast
    private var lastWidgetReload = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    private let refreshInterval: TimeInterval = 5 * 60
    private let planLifetime: TimeInterval = 6 * 3600

    init() {
        snapshot = SnapshotStore.load()
        cachedPlan = snapshot.map { ($0.plan, .distantPast) }
        startObserving()
        refreshSoon()
    }

    /// Coalesces bursts of requests, like a widget click right after waking up.
    func refreshSoon(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastRefresh) > 20 else { return }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefresh = Date()
        defer { isRefreshing = false }

        let activity = await scanner.scan()
        let credentials = await Task.detached(priority: .utility) { CredentialsReader.read() }.value
        let previous = snapshot
        let now = Date()

        guard let credentials else {
            let usesAPIKey = activity?.days.contains { $0.tokens > 0 } ?? false
            commit(UsageSnapshot(
                updatedAt: now,
                plan: usesAPIKey ? Plan(kind: .api, tier: nil) : previous?.plan ?? Plan(kind: .unknown, tier: nil),
                limits: [],
                extraUsage: nil,
                activity: activity,
                status: usesAPIKey ? .ok : .signedOut
            ))
            return
        }

        guard !credentials.isExpired else {
            commit(stale(previous, activity: activity, status: .expired, credentials: credentials))
            return
        }

        do {
            async let usageRequest = ClaudeAPI.usage(token: credentials.accessToken)
            let plan = await currentPlan(credentials: credentials)
            let usage = try await usageRequest
            commit(UsageSnapshot(
                updatedAt: now,
                plan: plan,
                limits: usage.usageLimits,
                extraUsage: usage.extra,
                activity: activity,
                status: .ok
            ))
        } catch ClaudeAPIError.unauthorized {
            commit(stale(previous, activity: activity, status: .expired, credentials: credentials))
        } catch {
            commit(stale(previous, activity: activity, status: .offline, credentials: credentials))
        }
    }

    // MARK: Private

    private func currentPlan(credentials: ClaudeCredentials) async -> Plan {
        if let cachedPlan, Date().timeIntervalSince(cachedPlan.fetchedAt) < planLifetime {
            return cachedPlan.plan
        }
        if let profile = try? await ClaudeAPI.profile(token: credentials.accessToken) {
            let plan = PlanDetector.plan(profile: profile, credentials: credentials)
            cachedPlan = (plan, Date())
            return plan
        }
        return cachedPlan?.plan ?? PlanDetector.plan(profile: nil, credentials: credentials)
    }

    /// Keeps the last known limits on screen when fresh numbers are not available.
    private func stale(_ previous: UsageSnapshot?, activity: Activity?, status: UsageSnapshot.Status, credentials: ClaudeCredentials) -> UsageSnapshot {
        var snapshot = previous ?? UsageSnapshot(
            updatedAt: Date(),
            plan: PlanDetector.plan(profile: nil, credentials: credentials),
            limits: [],
            extraUsage: nil,
            activity: nil,
            status: status
        )
        snapshot.activity = activity
        snapshot.status = status
        return snapshot
    }

    private func commit(_ next: UsageSnapshot) {
        let changed = !next.hasSameContent(as: snapshot)
        snapshot = next
        try? SnapshotStore.save(next)

        if changed || Date().timeIntervalSince(lastWidgetReload) > 30 * 60 {
            WidgetCenter.shared.reloadAllTimelines()
            lastWidgetReload = Date()
        }
    }

    private func startObserving() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSoon(force: true) }
        }
        timer?.tolerance = 30

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSoon(force: true) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .refreshRequested, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshSoon() }
        })

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .refreshRequested, object: nil)
                }
            },
            RefreshSignal.name as CFString,
            nil,
            .deliverImmediately
        )
    }
}

extension Notification.Name {
    static let refreshRequested = Notification.Name("ClawdmeterRefreshRequested")
}

private extension UsageSnapshot {
    func hasSameContent(as other: UsageSnapshot?) -> Bool {
        guard var other else { return false }
        other.updatedAt = updatedAt
        return self == other
    }
}
