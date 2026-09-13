import Foundation

enum Format {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// Compact time left, like "45m", "2h 13m" or "3d 4h".
    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        let days = hours / 24
        let rest = hours % 24
        return rest == 0 ? "\(days)d" : "\(days)d \(rest)h"
    }

    /// "Mon 02:00" for far away resets, a countdown when it is close.
    static func reset(_ date: Date, from now: Date) -> String {
        if date.timeIntervalSince(now) < 24 * 3600 {
            return "Resets in \(countdown(to: date, from: now))"
        }
        return "Resets \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    static func tokens(_ value: Int) -> String {
        let number = Double(value)
        switch value {
        case 1_000_000_000...: return trimmed(number / 1_000_000_000) + "B"
        case 1_000_000...: return trimmed(number / 1_000_000) + "M"
        case 10_000...: return "\(Int(number / 1000))K"
        case 1_000...: return trimmed(number / 1000) + "K"
        default: return "\(value)"
        }
    }

    static func money(_ value: Double, currencyCode: String) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(value < 100 ? 2 : 0)))
    }

    static func relative(_ date: Date, from now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        return "\(countdown(to: now, from: date)) ago"
    }

    private static func trimmed(_ value: Double) -> String {
        let text = String(format: value < 10 ? "%.1f" : "%.0f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}
