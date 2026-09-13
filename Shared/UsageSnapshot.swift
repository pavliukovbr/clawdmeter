import Foundation

struct UsageSnapshot: Codable, Equatable {
    var updatedAt: Date
    var plan: Plan
    var limits: [UsageLimit]
    var extraUsage: ExtraUsage?
    var activity: Activity?
    var status: Status

    enum Status: String, Codable {
        case ok
        case offline
        case expired
        case signedOut
    }

    var session: UsageLimit? { limits.first { $0.kind == .session } }
    var weekly: UsageLimit? { limits.first { $0.kind == .weekly } }
    var secondaryLimits: [UsageLimit] { limits.filter { $0.kind != .session } }
}

struct Plan: Codable, Equatable {
    enum Kind: String, Codable {
        case free, pro, max, team, enterprise, api, unknown
    }

    var kind: Kind
    var tier: String?

    var name: String {
        switch kind {
        case .free: "Free"
        case .pro: "Pro"
        case .max: tier.map { "Max \($0)" } ?? "Max"
        case .team: tier.map { "Team \($0)" } ?? "Team"
        case .enterprise: "Enterprise"
        case .api: "API"
        case .unknown: "Claude"
        }
    }

    var hasPlanLimits: Bool { kind != .api }
}

struct UsageLimit: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case session, weekly, model, other
    }

    enum Severity: String, Codable {
        case normal, warning, critical
    }

    var id: String
    var kind: Kind
    var title: String
    var percent: Double
    var resetsAt: Date?
    var severity: Severity

    /// Once the window has rolled over the usage starts again from zero.
    func percent(at date: Date) -> Double {
        if let resetsAt, resetsAt <= date { return 0 }
        return min(max(percent, 0), 100)
    }

    func severity(at date: Date) -> Severity {
        if let resetsAt, resetsAt <= date { return .normal }
        if severity != .normal { return severity }
        switch percent {
        case 90...: return .critical
        case 75...: return .warning
        default: return .normal
        }
    }
}

struct ExtraUsage: Codable, Equatable {
    var used: Double
    var limit: Double?
    var currencyCode: String

    var percent: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(used / limit * 100, 100)
    }
}

struct Activity: Codable, Equatable {
    struct Day: Codable, Equatable {
        var date: Date
        var tokens: Int
        var messages: Int
    }

    var days: [Day]
    var lastActiveAt: Date?

    var today: Day? { days.last.flatMap { Calendar.current.isDateInToday($0.date) ? $0 : nil } }
    var todayTokens: Int { today?.tokens ?? 0 }
    var todayMessages: Int { today?.messages ?? 0 }
}
