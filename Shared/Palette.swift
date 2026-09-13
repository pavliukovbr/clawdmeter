import SwiftUI

enum Palette {
    /// Clawd's own color.
    static let clay = Color(red: 215 / 255, green: 119 / 255, blue: 87 / 255)
    static let clayLight = Color(red: 236 / 255, green: 150 / 255, blue: 118 / 255)
    static let clayDeep = Color(red: 190 / 255, green: 92 / 255, blue: 62 / 255)

    static let amber = Color(red: 245 / 255, green: 178 / 255, blue: 76 / 255)
    static let amberDeep = Color(red: 222 / 255, green: 140 / 255, blue: 44 / 255)
    static let red = Color(red: 255 / 255, green: 105 / 255, blue: 94 / 255)
    static let redDeep = Color(red: 226 / 255, green: 62 / 255, blue: 58 / 255)

    static let sweat = Color(red: 140 / 255, green: 204 / 255, blue: 255 / 255)
    static let heart = Color(red: 255 / 255, green: 110 / 255, blue: 128 / 255)

    static let backgroundTop = Color(red: 52 / 255, green: 43 / 255, blue: 39 / 255)
    static let backgroundBottom = Color(red: 29 / 255, green: 25 / 255, blue: 23 / 255)

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    static func fill(for severity: UsageLimit.Severity) -> LinearGradient {
        let colors: [Color] = switch severity {
        case .normal: [clayDeep, clayLight]
        case .warning: [amberDeep, amber]
        case .critical: [redDeep, red]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    static func tint(for severity: UsageLimit.Severity) -> Color {
        switch severity {
        case .normal: clayLight
        case .warning: amber
        case .critical: red
        }
    }
}
