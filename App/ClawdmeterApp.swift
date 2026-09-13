import SwiftUI

@main
struct ClawdmeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuPanel(store: store)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Clawdmeter")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.enableOnFirstLaunch()
    }

    /// Opening the app again (or clicking the widget) brings the icon back and refreshes.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: "showMenuBarIcon")
        NotificationCenter.default.post(name: .refreshRequested, object: nil)
        return false
    }
}
