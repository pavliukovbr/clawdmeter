import AppIntents
import SwiftUI

/// Clicking Clawd in the widget shows a heart for a moment and asks the app for fresh numbers.
struct PetClawdIntent: AppIntent {
    static var title: LocalizedStringResource = "Pet Clawd"
    static var description = IntentDescription("Say hi to Clawd and refresh your usage.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        PetState.pet()
        RefreshSignal.post()
        return .result()
    }
}

enum PetState {
    static let duration: TimeInterval = 2.5
    private static let key = "pettedAt"

    static func pet(at date: Date = .now) {
        UserDefaults.standard.set(date, forKey: key)
    }

    static var pettedUntil: Date? {
        (UserDefaults.standard.object(forKey: key) as? Date).map { $0.addingTimeInterval(duration) }
    }
}

/// A Darwin notification is one of the few things a sandboxed widget can send to its app.
enum RefreshSignal {
    static let name = "com.pavliukovbr.clawdmeter.refresh"

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }
}

private struct InteractivePetKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var interactivePet: Bool {
        get { self[InteractivePetKey.self] }
        set { self[InteractivePetKey.self] = newValue }
    }
}
