import BackgroundTasks
import SwiftUI

@main
struct ClawdmeterPhoneApp: App {
    static let refreshTask = "clawdmeter.refresh"

    @StateObject private var model = PhoneModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onOpenURL { model.pair(with: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.refresh() }
            case .background:
                Self.scheduleRefresh()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(Self.refreshTask)) {
            await model.refresh()
            Self.scheduleRefresh()
        }
    }

    /// iOS decides when this actually runs, usually every so often while the phone is in use.
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
