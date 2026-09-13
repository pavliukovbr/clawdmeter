import Foundation

/// What the widget shows for a snapshot at a given moment, whatever the plan.
struct UsageSummary {
    struct Metric: Identifiable {
        var id: String
        var title: String
        var shortTitle: String?
        var value: String
        var fraction: Double
        var severity: UsageLimit.Severity
        var detail: String?
    }

    var planName: String
    var primary: Metric
    var secondary: [Metric]
    var mood: ClawdMood
    var activity: Activity?
    var note: String?
    var hasData: Bool

    init(snapshot: UsageSnapshot?, date: Date) {
        guard let snapshot else {
            planName = "Clawdmeter"
            primary = Metric(id: "empty", title: "Waiting for data", value: "Hi!", fraction: 0, severity: .normal, detail: nil)
            secondary = []
            mood = .sleeping
            activity = nil
            note = "Open the app to start"
            hasData = false
            return
        }

        planName = snapshot.plan.name
        activity = snapshot.activity
        hasData = true

        var limits = snapshot.limits.map { Self.metric(for: $0, date: date) }
        if let extra = snapshot.extraUsage, let metric = Self.metric(for: extra) {
            limits.append(metric)
        }

        if let first = limits.first {
            primary = first
            secondary = Array(limits.dropFirst())
        } else {
            primary = Self.tokenMetric(for: snapshot.activity)
            secondary = []
        }

        mood = Self.mood(for: snapshot, date: date)
        note = Self.note(for: snapshot, date: date)
    }

    private static func metric(for limit: UsageLimit, date: Date) -> Metric {
        let percent = limit.percent(at: date)
        var detail: String?
        if let resetsAt = limit.resetsAt, resetsAt > date {
            detail = Format.reset(resetsAt, from: date)
        } else if limit.resetsAt != nil {
            detail = "Fresh window"
        }
        return Metric(
            id: limit.id,
            title: limit.title,
            value: Format.percent(percent),
            fraction: percent / 100,
            severity: limit.severity(at: date),
            detail: detail
        )
    }

    private static func metric(for extra: ExtraUsage) -> Metric? {
        let used = Format.money(extra.used, currencyCode: extra.currencyCode)
        guard let percent = extra.percent, let limit = extra.limit else {
            return Metric(id: "extra", title: "Extra usage", shortTitle: "Extra", value: used, fraction: 0, severity: .normal, detail: "No monthly cap")
        }
        let severity: UsageLimit.Severity = percent >= 90 ? .critical : percent >= 75 ? .warning : .normal
        return Metric(
            id: "extra",
            title: "Extra usage",
            shortTitle: "Extra",
            value: Format.percent(percent),
            fraction: percent / 100,
            severity: severity,
            detail: "\(used) of \(Format.money(limit, currencyCode: extra.currencyCode))"
        )
    }

    private static func tokenMetric(for activity: Activity?) -> Metric {
        let today = activity?.todayTokens ?? 0
        let busiest = activity?.days.map(\.tokens).max() ?? 0
        return Metric(
            id: "tokens",
            title: "Tokens today",
            value: Format.tokens(today),
            fraction: busiest > 0 ? Double(today) / Double(busiest) : 0,
            severity: .normal,
            detail: activity.map { "\($0.todayMessages) requests" }
        )
    }

    private static func mood(for snapshot: UsageSnapshot, date: Date) -> ClawdMood {
        let sinceActive = snapshot.activity?.lastActiveAt.map { date.timeIntervalSince($0) } ?? .infinity
        let workingNow = sinceActive < 3 * 60

        guard let session = snapshot.session else {
            if workingNow { return .busy }
            return sinceActive > 30 * 60 ? .sleeping : .idle
        }

        let percent = session.percent(at: date)
        let weekly = snapshot.weekly?.percent(at: date) ?? 0
        if percent >= 100 { return .sleeping }
        if percent >= 80 || weekly >= 90 { return .tired }
        if percent >= 50 || weekly >= 75 || workingNow { return .busy }

        let windowOpen = session.resetsAt.map { $0 > date } ?? false
        if !windowOpen && sinceActive > 30 * 60 { return .sleeping }
        return .idle
    }

    private static func note(for snapshot: UsageSnapshot, date: Date) -> String? {
        switch snapshot.status {
        case .signedOut:
            return "Sign in to Claude Code"
        case .expired:
            return "Open Claude Code to reconnect"
        case .offline where date.timeIntervalSince(snapshot.updatedAt) > 15 * 60:
            return "Updated \(Format.relative(snapshot.updatedAt, from: date))"
        default:
            if date.timeIntervalSince(snapshot.updatedAt) > 45 * 60 {
                return "Updated \(Format.relative(snapshot.updatedAt, from: date))"
            }
            return nil
        }
    }
}
