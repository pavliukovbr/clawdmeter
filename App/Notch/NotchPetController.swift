import AppKit
import Combine

/// Keeps a click through panel under the notch with Clawd in it. On Macs without a notch
/// Clawd hangs from the middle of the menu bar instead.
@MainActor
final class NotchPetController {
    static let enabledKey = "notchPetEnabled"

    private let store: UsageStore
    private let watcher: ClaudeActivityWatcher
    private var panel: NSPanel?
    private var scene: NotchSceneView?
    private var tracker: ActivityTracker?
    private var petZone: CGRect = .zero
    private var subscriptions: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitors: [Any] = []
    private var revealWork: DispatchWorkItem?
    private var fullscreenTimer: Timer?

    init(store: UsageStore, watcher: ClaudeActivityWatcher) {
        self.store = store
        self.watcher = watcher
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySetting() }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkFullscreen() }
            })
        }
        applySetting()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    private func applySetting() {
        if isEnabled, panel == nil {
            start()
        } else if !isEnabled, panel != nil {
            stop()
        }
    }

    private func restart() {
        stop()
        applySetting()
    }

    // MARK: Lifecycle

    private func start() {
        guard let geometry = NotchGeometry.current() else { return }
        let notch = geometry.notch
        let side: CGFloat = 70
        let height = notch.height + NotchSceneView.depth
        let frame = CGRect(x: notch.minX - side, y: notch.maxY - height, width: notch.width + side * 2, height: height)

        let panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let scene = NotchSceneView(size: frame.size, ceiling: notch.height)
        panel.contentView = scene
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        self.scene = scene

        petZone = CGRect(x: notch.midX - 36, y: notch.minY - NotchSceneView.depth, width: 72, height: NotchSceneView.depth)
            .insetBy(dx: -18, dy: -12)

        let tracker = ActivityTracker(watcher: watcher)
        tracker.$activity
            .removeDuplicates()
            .sink { [weak scene] in scene?.show($0) }
            .store(in: &subscriptions)
        store.$snapshot
            .map { snapshot in (snapshot?.session?.percent(at: Date()) ?? 0) >= 100 }
            .removeDuplicates()
            .sink { [weak tracker] in tracker?.limitReached = $0 }
            .store(in: &subscriptions)
        tracker.start()
        self.tracker = tracker

        let moved: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: moved) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in
            moved(event)
            return event
        }) {
            mouseMonitors.append(local)
        }

        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFullscreen() }
        }
        fullscreenTimer?.tolerance = 1
        checkFullscreen()
    }

    private func stop() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
        fullscreenTimer?.invalidate()
        fullscreenTimer = nil
        revealWork?.cancel()
        tracker?.stop()
        tracker = nil
        subscriptions = []
        panel?.orderOut(nil)
        panel = nil
        scene = nil
    }

    // MARK: Staying out of the way

    /// Clawd ducks behind the notch while the pointer is close, so the tabs and title bar
    /// underneath stay easy to reach.
    private func pointerMoved() {
        guard let scene else { return }
        if petZone.contains(NSEvent.mouseLocation) {
            revealWork?.cancel()
            revealWork = nil
            scene.setHidden(true, reason: .pointer)
        } else if revealWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.revealWork = nil
                self?.scene?.setHidden(false, reason: .pointer)
            }
            revealWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
    }

    /// Full screen spaces hide the menu bar window, which is an easy thing to look for
    /// without any extra permissions.
    private func checkFullscreen() {
        guard let scene, let screen = panel?.screen ?? NSScreen.main else { return }
        scene.setHidden(Self.isMenuBarHidden(on: screen), reason: .fullscreen)
    }

    private static func isMenuBarHidden(on screen: NSScreen) -> Bool {
        if UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["_HIHideMenuBar"] as? Bool == true {
            return false
        }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let topEdge = CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY, width: screen.frame.width, height: 4)
        for window in windows where window[kCGWindowLayer as String] as? Int == menuBarLevel {
            if let bounds = window[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: bounds),
               rect.intersects(topEdge) {
                return false
            }
        }
        return true
    }
}

struct NotchGeometry {
    var notch: CGRect
    var hasNotch: Bool

    static func current() -> NotchGeometry? {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let height = screen.safeAreaInsets.top
            let width = screen.frame.width - left.width - right.width
            let notch = CGRect(x: screen.frame.minX + left.width, y: screen.frame.maxY - height, width: width, height: height)
            return NotchGeometry(notch: notch, hasNotch: true)
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let notch = CGRect(x: screen.frame.midX - 90, y: screen.frame.maxY - menuBar, width: 180, height: menuBar)
        return NotchGeometry(notch: notch, hasNotch: false)
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
