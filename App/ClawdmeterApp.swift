import SwiftUI

@main
struct ClawdmeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuPanel(store: appDelegate.store, updater: appDelegate.updater, keepAwake: appDelegate.keepAwake, oldPhoneScreen: appDelegate.oldPhoneScreen)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Clawdmeter")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    let watcher = ClaudeActivityWatcher()
    let updater = Updater()
    let keepAwake: KeepAwake
    let oldPhoneScreen: OldPhoneScreen
    private var notchPet: NotchPetController?
    private var roaming: RoamingController?
    private var notifier: ClaudeNotifier?

    override init() {
        // The iPhone app is retired, so its server stays off even for anyone who had it on.
        UserDefaults.standard.set(false, forKey: PhoneSharing.enabledKey)
        keepAwake = KeepAwake(watcher: watcher)
        oldPhoneScreen = OldPhoneScreen(store: store, watcher: watcher)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.enableOnFirstLaunch()
        watcher.start()
        let notchPet = NotchPetController(store: store, watcher: watcher)
        self.notchPet = notchPet
        roaming = RoamingController(watcher: watcher, notchPet: notchPet)
        notifier = ClaudeNotifier(watcher: watcher)
    }

    /// Opening the app again (or clicking the widget) brings the icon back and refreshes.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: "showMenuBarIcon")
        NotificationCenter.default.post(name: .refreshRequested, object: nil)
        return false
    }
}
