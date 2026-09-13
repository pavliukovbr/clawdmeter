import Foundation

struct ClaudeCredentials {
    var accessToken: String
    var expiresAt: Date?
    var subscriptionType: String?
    var rateLimitTier: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date().addingTimeInterval(60)
    }
}

/// Reads the sign in that Claude Code already stores on this Mac.
/// The token stays in memory and is only ever sent to api.anthropic.com.
enum CredentialsReader {
    static func read() -> ClaudeCredentials? {
        if let data = keychainItem(), let credentials = parse(data) {
            return credentials
        }
        let file = URL(fileURLWithPath: SnapshotStore.realHomeDirectory).appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file), let credentials = parse(data) {
            return credentials
        }
        return nil
    }

    /// Claude Code writes this item with the security tool, so reading it the same way
    /// does not trigger a keychain prompt.
    private static func keychainItem() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private static func parse(_ data: Data) -> ClaudeCredentials? {
        struct Stored: Decodable {
            struct OAuth: Decodable {
                var accessToken: String
                var expiresAt: Double?
                var subscriptionType: String?
                var rateLimitTier: String?
            }
            var claudeAiOauth: OAuth?
        }

        guard let oauth = try? JSONDecoder().decode(Stored.self, from: data).claudeAiOauth,
              !oauth.accessToken.isEmpty else { return nil }
        return ClaudeCredentials(
            accessToken: oauth.accessToken,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            subscriptionType: oauth.subscriptionType,
            rateLimitTier: oauth.rateLimitTier
        )
    }
}

enum ClaudeAPIError: Error {
    case unauthorized
    case http(Int)
}

enum ClaudeAPI {
    private static let base = URL(string: "https://api.anthropic.com/api/oauth/")!

    static func usage(token: String) async throws -> UsageResponse {
        try await get("usage", token: token)
    }

    static func profile(token: String) async throws -> ProfileResponse {
        try await get("profile", token: token)
    }

    private static func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw ClaudeAPIError.unauthorized }
        guard (200..<300).contains(status) else { throw ClaudeAPIError.http(status) }
        return try decoder.decode(T.self, from: data)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
            }
            return date
        }
        return decoder
    }()

    /// The API sends microseconds, which ISO8601DateFormatter does not accept, so drop them.
    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}

// MARK: Responses

struct UsageResponse: Decodable {
    struct Window: Decodable {
        var utilization: Double?
        var resetsAt: Date?
    }

    struct Limit: Decodable {
        struct Scope: Decodable {
            struct Named: Decodable {
                var id: String?
                var displayName: String?
            }
            var model: Named?
            var surface: Named?
        }

        var kind: String?
        var group: String?
        var percent: Double?
        var severity: String?
        var resetsAt: Date?
        var scope: Scope?
    }

    struct Extra: Decodable {
        var isEnabled: Bool?
        var monthlyLimit: Double?
        var usedCredits: Double?
        var currency: String?
        var decimalPlaces: Int?
    }

    struct Spend: Decodable {
        struct Amount: Decodable {
            var amountMinor: Double?
            var currency: String?
            var exponent: Int?

            var value: Double? {
                amountMinor.map { $0 / pow(10, Double(exponent ?? 2)) }
            }
        }
        var used: Amount?
        var limit: Amount?
        var enabled: Bool?
    }

    var fiveHour: Window?
    var sevenDay: Window?
    var sevenDayOpus: Window?
    var sevenDaySonnet: Window?
    var limits: [Limit]?
    var extraUsage: Extra?
    var spend: Spend?
}

struct ProfileResponse: Decodable {
    struct Account: Decodable {
        var hasClaudeMax: Bool?
        var hasClaudePro: Bool?
    }

    struct Organization: Decodable {
        var organizationType: String?
        var rateLimitTier: String?
        var seatTier: String?
        var billingType: String?
    }

    var account: Account?
    var organization: Organization?
}

// MARK: Mapping

extension UsageResponse {
    var usageLimits: [UsageLimit] {
        if let limits, !limits.isEmpty {
            return limits.compactMap(Self.map).sorted { $0.kind.order < $1.kind.order }
        }

        var result: [UsageLimit] = []
        let windows: [(Window?, UsageLimit.Kind, String, String)] = [
            (fiveHour, .session, "session", "Session"),
            (sevenDay, .weekly, "weekly_all", "Weekly"),
            (sevenDayOpus, .model, "weekly_opus", "Opus"),
            (sevenDaySonnet, .model, "weekly_sonnet", "Sonnet"),
        ]
        for (window, kind, id, title) in windows {
            guard let window, let utilization = window.utilization else { continue }
            result.append(UsageLimit(id: id, kind: kind, title: title, percent: utilization, resetsAt: window.resetsAt, severity: .normal))
        }
        return result
    }

    var extra: ExtraUsage? {
        if let extraUsage, extraUsage.isEnabled == true, let used = extraUsage.usedCredits {
            let divisor = pow(10, Double(extraUsage.decimalPlaces ?? 0))
            return ExtraUsage(
                used: used / divisor,
                limit: extraUsage.monthlyLimit.map { $0 / divisor },
                currencyCode: extraUsage.currency ?? "USD"
            )
        }
        if let spend, spend.enabled == true, let used = spend.used?.value {
            return ExtraUsage(used: used, limit: spend.limit?.value, currencyCode: spend.used?.currency ?? "USD")
        }
        return nil
    }

    private static func map(_ limit: Limit) -> UsageLimit? {
        guard let percent = limit.percent else { return nil }
        let scopeName = limit.scope?.model?.displayName ?? limit.scope?.surface?.displayName

        let kind: UsageLimit.Kind
        let title: String
        switch limit.kind {
        case "session":
            kind = .session
            title = "Session"
        case "weekly_all":
            kind = .weekly
            title = "Weekly"
        case "weekly_scoped":
            kind = .model
            title = scopeName ?? "Weekly"
        default:
            kind = limit.group == "session" ? .session : .other
            title = scopeName ?? (limit.kind ?? limit.group ?? "Limit")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        let id = [limit.kind ?? limit.group ?? "limit", scopeName].compactMap { $0 }.joined(separator: ".")
        return UsageLimit(
            id: id,
            kind: kind,
            title: title,
            percent: percent,
            resetsAt: limit.resetsAt,
            severity: UsageLimit.Severity(rawValue: limit.severity ?? "") ?? .normal
        )
    }
}

private extension UsageLimit.Kind {
    var order: Int {
        switch self {
        case .session: 0
        case .weekly: 1
        case .model: 2
        case .other: 3
        }
    }
}

enum PlanDetector {
    static func plan(profile: ProfileResponse?, credentials: ClaudeCredentials) -> Plan {
        let organization = profile?.organization
        let type = (organization?.organizationType ?? "").lowercased()
        let tier = (organization?.rateLimitTier ?? credentials.rateLimitTier ?? "").lowercased()
        let subscription = (credentials.subscriptionType ?? "").lowercased()
        let hints = [type, subscription]

        if hints.contains(where: { $0.contains("enterprise") }) {
            return Plan(kind: .enterprise, tier: nil)
        }
        if hints.contains(where: { $0.contains("team") }) {
            return Plan(kind: .team, tier: seatName(organization?.seatTier))
        }
        if hints.contains(where: { $0.contains("max") }) || tier.contains("max") || profile?.account?.hasClaudeMax == true {
            return Plan(kind: .max, tier: multiplier(in: tier))
        }
        if hints.contains(where: { $0.contains("pro") }) || tier.contains("pro") || profile?.account?.hasClaudePro == true {
            return Plan(kind: .pro, tier: nil)
        }
        if hints.contains(where: { $0.contains("free") }) || tier.contains("free") {
            return Plan(kind: .free, tier: nil)
        }
        if type.contains("api") || type.contains("console") {
            return Plan(kind: .api, tier: nil)
        }
        return Plan(kind: type.isEmpty && subscription.isEmpty ? .unknown : .free, tier: nil)
    }

    /// "default_claude_max_20x" becomes "20×".
    private static func multiplier(in tier: String) -> String? {
        guard let range = tier.range(of: #"\d+x"#, options: .regularExpression) else { return nil }
        return String(tier[range].dropLast()) + "×"
    }

    /// Premium seats get a label, standard seats are just Team.
    private static func seatName(_ seat: String?) -> String? {
        guard let seat = seat?.lowercased(), seat.contains("premium") else { return nil }
        return "Premium"
    }
}
