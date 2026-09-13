import Foundation

extension UsageSnapshot {
    /// Shown in the widget gallery before any real data exists.
    static var preview: UsageSnapshot {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tokens = [6_400_000, 11_200_000, 2_900_000, 15_800_000, 9_100_000, 12_600_000, 7_300_000]
        let days = tokens.enumerated().map { index, value in
            Activity.Day(
                date: calendar.date(byAdding: .day, value: index - tokens.count + 1, to: today) ?? today,
                tokens: value,
                messages: value / 9_000
            )
        }

        return UsageSnapshot(
            updatedAt: now,
            plan: Plan(kind: .max, tier: "5×"),
            limits: [
                UsageLimit(id: "session", kind: .session, title: "Session", percent: 32, resetsAt: now.addingTimeInterval(2 * 3600 + 18 * 60), severity: .normal),
                UsageLimit(id: "weekly_all", kind: .weekly, title: "Weekly", percent: 58, resetsAt: now.addingTimeInterval(3 * 86400), severity: .normal),
            ],
            extraUsage: nil,
            activity: Activity(days: days, lastActiveAt: now.addingTimeInterval(-20 * 60)),
            status: .ok
        )
    }
}
