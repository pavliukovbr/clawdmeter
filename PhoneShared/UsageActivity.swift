import ActivityKit
import Foundation

struct UsageActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var planName: String
        var title: String
        var percent: Double
        var resetsAt: Date?
        var severity: UsageLimit.Severity
        var weeklyPercent: Double?
        var mood: ClawdMood
        var updatedAt: Date
    }

    var macName: String
}

extension UsageActivityAttributes.ContentState {
    init(snapshot: UsageSnapshot, now: Date = Date()) {
        let summary = UsageSummary(snapshot: snapshot, date: now)
        let session = snapshot.session
        planName = summary.planName
        title = summary.primary.title
        percent = summary.primary.fraction * 100
        resetsAt = session?.resetsAt.flatMap { $0 > now ? $0 : nil }
        severity = summary.primary.severity
        weeklyPercent = snapshot.weekly?.percent(at: now)
        mood = summary.mood
        updatedAt = now
    }
}
