import Combine
import Foundation
import IOKit.pwr_mgt

/// Stops the Mac from going to sleep on its own, so Claude can keep working while you are
/// away. The hold is released as soon as it is not needed or the app quits.
@MainActor
final class KeepAwake: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case off, whileClaudeWorks, always

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "Off"
            case .whileClaudeWorks: "While Claude Works"
            case .always: "Always"
            }
        }
    }

    static let modeKey = "keepAwakeMode"
    static let displayKey = "keepDisplayAwake"

    @Published private(set) var isActive = false

    private let watcher: ClaudeActivityWatcher
    private var assertion: IOPMAssertionID = 0
    private var assertionKeepsDisplay = false
    private var timer: Timer?
    private var subscriptions: Set<AnyCancellable> = []

    init(watcher: ClaudeActivityWatcher) {
        self.watcher = watcher
        UserDefaults.standard.register(defaults: [Self.modeKey: Mode.off.rawValue, Self.displayKey: false])

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &subscriptions)
        watcher.$latest
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &subscriptions)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer?.tolerance = 10
        update()
    }

    var mode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .off
    }

    private func update() {
        let keepDisplay = UserDefaults.standard.bool(forKey: Self.displayKey)
        switch mode {
        case .off:
            release()
        case .always:
            hold(keepDisplay: keepDisplay)
        case .whileClaudeWorks:
            // Ten quiet minutes after the last step, or longer while a tool is still running.
            if watcher.isClaudeWorking(within: 10 * 60) {
                hold(keepDisplay: keepDisplay)
            } else {
                release()
            }
        }
        isActive = assertion != 0
    }

    private func hold(keepDisplay: Bool) {
        if assertion != 0, assertionKeepsDisplay == keepDisplay { return }
        release()
        let type = keepDisplay ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Clawdmeter is keeping the Mac awake so Claude can keep working" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertion = id
            assertionKeepsDisplay = keepDisplay
        }
    }

    private func release() {
        guard assertion != 0 else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
    }
}
