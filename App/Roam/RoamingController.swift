import AppKit
import Combine
import QuartzCore

/// Lets Clawd out of the notch to wander around the desktop. He sits on the menu bar next
/// to the notch, drops onto windows, rides them when you drag them, falls when they close,
/// jumps between them and now and then pretends to be something else on the screen.
/// There is only ever one Clawd: while he is out, the notch stays empty.
@MainActor
final class RoamingController: NSObject {
    static let enabledKey = "clawdWalksAround"

    private enum Mode {
        case away, falling, walking, idle, jumping, disguised, resting, swinging, partying
    }

    private struct Jump {
        var from: CGPoint
        var to: CGPoint
        var target: Surface
        var start: CFTimeInterval
        var duration: CFTimeInterval
        var height: CGFloat
    }

    private struct Disguise {
        var look: RoamingSprite.Look
        var until: CFTimeInterval
        var returnPoint: CGPoint
        var windowID: Int?
    }

    /// Web slinging: a pendulum from an anchor under the menu bar, then the next one.
    private struct Swing {
        var direction: CGFloat
        var anchor: CGPoint
        var length: CGFloat
        var angle: CGFloat
        var start: CFTimeInterval
        var zipFrom: CGPoint?
        var count = 0
    }

    private let watcher: ClaudeActivityWatcher
    private let notchPet: NotchPetController?
    private var panel: NSPanel?
    private var hostView: NSView?
    private var sprite: RoamingSprite?
    private var effects = CALayer()
    private var web = CAShapeLayer()
    private var displayLink: CADisplayLink?
    private var presenceTimer: Timer?
    private var subscriptions: Set<AnyCancellable> = []

    private var screenSize = CGSize.zero
    private var surfaces: [Surface] = []
    private var lastScan: CFTimeInterval = 0
    private var lastFrame: CFTimeInterval = 0

    private var mode: Mode = .away
    private var position = CGPoint.zero
    private var fallSpeed: CGFloat = 0
    private var driftX: CGFloat = 0
    private var direction: CGFloat = 1
    private var walkTarget: CGFloat = 0
    private var standing: Surface?
    private var decideAt: CFTimeInterval = 0
    private var jump: Jump?
    private var disguise: Disguise?
    private var swing: Swing?
    private var partyUntil: CFTimeInterval = 0
    private var finishingEasterEgg = false
    private var partyPending = false
    private var perchLeaveAt: CFTimeInterval = 0
    private var nextDisguise: CFTimeInterval = CACurrentMediaTime() + 40
    private var nextApple: CFTimeInterval = CACurrentMediaTime() + 150
    private var hoverSince: CFTimeInterval?
    private var pettedUntil: CFTimeInterval = 0
    private var quietSince = Date()
    private var stayHomeUntil = Date.distantPast
    private var lastTransition = Date.distantPast
    private var easterEggUntil = Date.distantPast
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private static let leftPerch = -1
    private static let rightPerch = -2

    init(watcher: ClaudeActivityWatcher, notchPet: NotchPetController?) {
        self.watcher = watcher
        self.notchPet = notchPet
        super.init()
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluatePresence() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildWindow() }
            .store(in: &subscriptions)
        watcher.$lastFinishedTurn
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] turn in self?.celebrate(turn) }
            .store(in: &subscriptions)
        watcher.$easterEgg
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] egg in self?.playEasterEgg(egg) }
            .store(in: &subscriptions)

        presenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluatePresence() }
        }
        presenceTimer?.tolerance = 0.3
        evaluatePresence()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey) && !reduceMotion
    }

    // MARK: Out or home

    /// Decides once a second whether Clawd is out on the desktop or at home in the notch.
    private func evaluatePresence() {
        guard isEnabled, let screen = NSScreen.screens.first else {
            goAway(animated: false)
            tearDown()
            return
        }
        if panel == nil { rebuildWindow() }

        let now = Date()
        let claudeBusy = watcher.isClaudeWorking(within: 30) && ![.celebrating, .idle].contains(watcher.latest?.activity)
        let anyInput = CGEventType(rawValue: ~0) ?? .mouseMoved
        let userAway = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) > 5 * 60
        if claudeBusy || userAway { quietSince = now }

        let fullscreen = NotchPetController.isMenuBarHidden(on: screen)
        hostView?.isHidden = fullscreen
        guard !fullscreen, now >= easterEggUntil else { return }

        if notchPet?.isShowing == true {
            let sinceChange = now.timeIntervalSince(lastTransition)
            let wantsOut = !claudeBusy && !userAway && now.timeIntervalSince(quietSince) > 8 && now >= stayHomeUntil
            if mode == .away {
                if wantsOut, sinceChange > 10 { comeOut(fromNotch: true) }
            } else if userAway || (claudeBusy && sinceChange > 20) {
                goAway(animated: true)
            }
        } else {
            if mode == .away { comeOut(fromNotch: false) }
            guard let sprite, [.idle, .walking, .resting].contains(mode), standing != nil else { return }
            if userAway {
                sprite.setPose(.sleep)
                mode = .resting
            } else if claudeBusy {
                sprite.setPose(.work)
                mode = .resting
            } else if mode == .resting {
                sprite.setPose(.stand)
                mode = .idle
                decideAt = CACurrentMediaTime() + 1
            }
        }
    }

    /// Either walks out from behind the notch onto the menu bar beside it, or drops straight down.
    private func comeOut(fromNotch: Bool) {
        guard let sprite else { return }
        scanSurfaces()
        notchPet?.setAway(true)
        lastTransition = Date()
        sprite.reset()
        sprite.layer.transform = CATransform3DIdentity
        sprite.layer.isHidden = false
        displayLink?.isPaused = false
        fallSpeed = 0
        driftX = 0

        let perches = surfaces.filter(\.isPerch)
        if fromNotch, Bool.random(), let perch = perches.randomElement() {
            let fromLeft = perch.id == Self.leftPerch
            position = CGPoint(x: fromLeft ? perch.maxX : perch.minX, y: perch.y)
            standing = perch
            direction = fromLeft ? -1 : 1
            walkTarget = position.x + direction * CGFloat.random(in: 20...44)
            sprite.facingLeft = direction < 0
            sprite.setPose(.walk)
            mode = .walking
            perchLeaveAt = CACurrentMediaTime() + Double.random(in: 7...16)
        } else {
            let start = notchPet?.dropPoint ?? CGPoint(x: screenSize.width / 2, y: menuBarHeight() + 4)
            position = CGPoint(x: start.x, y: start.y + sprite.size.height)
            standing = nil
            mode = .falling
            sprite.setPose(.fall)
        }
        place()
    }

    private func goAway(animated: Bool) {
        guard mode != .away else { return }
        mode = .away
        disguise = nil
        jump = nil
        swing = nil
        web.path = nil
        lastTransition = Date()
        let finish = { [weak self] in
            guard let self, self.mode == .away else { return }
            self.sprite?.layer.isHidden = true
            self.displayLink?.isPaused = true
            self.notchPet?.setAway(false)
        }
        if animated, let sprite {
            sprite.vanish { finish() }
        } else {
            finish()
        }
    }

    private func celebrate(_ turn: FinishedTurn) {
        guard Date().timeIntervalSince(turn.date) < 60, [.idle, .walking, .resting].contains(mode), let sprite else { return }
        sprite.setPose(.happy)
        sprite.sparkle()
        mode = .idle
        decideAt = CACurrentMediaTime() + 2.5
    }

    // MARK: Window

    private func rebuildWindow() {
        tearDown()
        guard isEnabled, let screen = NSScreen.screens.first else { return }
        screenSize = screen.frame.size

        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = FlippedLayerView(frame: CGRect(origin: .zero, size: screen.frame.size))
        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()

        effects = CALayer()
        effects.frame = view.bounds
        web = CAShapeLayer()
        web.frame = view.bounds
        web.strokeColor = NSColor(white: 0.97, alpha: 0.95).cgColor
        web.lineWidth = 1.4
        web.lineCap = .round
        web.shadowColor = NSColor.black.cgColor
        web.shadowOpacity = 0.35
        web.shadowRadius = 1
        web.shadowOffset = .zero
        view.layer?.addSublayer(effects)
        view.layer?.addSublayer(web)

        let sprite = RoamingSprite()
        sprite.layer.isHidden = true
        view.layer?.addSublayer(sprite.layer)

        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        link.isPaused = true

        self.panel = panel
        hostView = view
        self.sprite = sprite
        displayLink = link
        mode = .away
    }

    private func tearDown() {
        displayLink?.invalidate()
        displayLink = nil
        panel?.orderOut(nil)
        panel = nil
        hostView = nil
        sprite = nil
        mode = .away
    }

    // MARK: Every frame

    @objc private func step(_ link: CADisplayLink) {
        guard let sprite, mode != .away else { return }
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastFrame, 0), 1.0 / 20))
        lastFrame = now

        if now - lastScan > 0.1 {
            scanSurfaces()
            lastScan = now
        }
        watchPointer(now: now)

        switch mode {
        case .away:
            return

        case .falling:
            fallSpeed = min(fallSpeed + 1700 * dt, 1100)
            let nextY = position.y + fallSpeed * dt
            position.x = min(max(position.x + driftX * dt, 12), screenSize.width - 12)
            driftX *= max(0, 1 - 1.4 * dt)
            if fallSpeed > 0, let surface = landing(from: position.y, to: nextY, x: position.x) {
                land(on: surface, now: now)
            } else {
                position.y = nextY
                if position.y > screenSize.height + 80 {
                    position = CGPoint(x: CGFloat.random(in: 80...(screenSize.width - 80)), y: 0)
                }
            }

        case .walking:
            guard let surface = standing else { break }
            position.x += direction * 36 * dt
            let reachedTarget = direction > 0 ? position.x >= walkTarget : position.x <= walkTarget
            let atEdge = position.x <= surface.minX + 4 || position.x >= surface.maxX - 4
            if atEdge, !surface.isFloor, !surface.isPerch, Double.random(in: 0..<1) < 0.4 {
                standing = nil
                fallSpeed = -120
                driftX = direction * 40
                mode = .falling
                sprite.setPose(.fall)
            } else if reachedTarget || atEdge {
                position.x = min(max(position.x, surface.minX + 4), surface.maxX - 4)
                sprite.setPose(.stand)
                mode = .idle
                decideAt = now + Double.random(in: 1.5...4)
            }

        case .jumping:
            guard let jump else { break }
            let t = CGFloat(min((now - jump.start) / jump.duration, 1))
            position.x = jump.from.x + (jump.to.x - jump.from.x) * t
            position.y = jump.from.y + (jump.to.y - jump.from.y) * t - jump.height * 4 * t * (1 - t)
            if t >= 1 {
                self.jump = nil
                if let surface = surfaces.first(where: { $0.id == jump.target.id && $0.contains(position.x, margin: 4) }) {
                    land(on: surface, now: now)
                } else {
                    standing = nil
                    fallSpeed = 0
                    mode = .falling
                    sprite.setPose(.fall)
                }
            }

        case .idle:
            if now >= decideAt, now >= pettedUntil { decide(now: now) }

        case .disguised:
            updateDisguise(now: now)

        case .swinging:
            updateSwing(now: now)

        case .partying:
            if now >= partyUntil { finishParty(now: now) }

        case .resting:
            break
        }

        if [.walking, .idle, .resting, .partying].contains(mode), standing == nil {
            fallSpeed = 0
            mode = .falling
            sprite.setPose(.fall)
        }
        place()
    }

    private func land(on surface: Surface, now: CFTimeInterval) {
        guard let sprite else { return }
        position.y = surface.y
        standing = surface
        fallSpeed = 0
        driftX = 0
        sprite.setPose(finishingEasterEgg ? .happy : .stand)
        sprite.land()
        mode = .idle
        decideAt = now + (finishingEasterEgg ? 1.6 : Double.random(in: 0.8...2))
        if partyPending { beginParty() }
    }

    private func place() {
        guard let sprite else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.layer.position = CGPoint(x: position.x.rounded(), y: position.y.rounded())
        CATransaction.commit()
    }

    // MARK: Surfaces

    private func scanSurfaces() {
        guard let screen = NSScreen.screens.first else { return }
        surfaces = ScreenSurfaces.current(on: screen, ignoring: ProcessInfo.processInfo.processIdentifier) + perches(on: screen)
        guard let current = standing else { return }

        // Ride along when the window underneath moves, and fall when it goes away.
        let candidates = surfaces.filter { $0.id == current.id }
        if let moved = candidates.min(by: { distance(to: $0) < distance(to: $1) }) {
            if let old = current.windowFrame, let new = moved.windowFrame {
                position.x += new.minX - old.minX
            }
            position.y = moved.y
            standing = moved.contains(position.x, margin: 2) ? moved : nil
        } else {
            standing = nil
        }
    }

    /// The bits of menu bar right next to the notch, where Clawd likes to sit.
    private func perches(on screen: NSScreen) -> [Surface] {
        guard let notch = NotchGeometry.current()?.notch else { return [] }
        let left = notch.minX - screen.frame.minX
        let right = notch.maxX - screen.frame.minX
        let y = screen.frame.maxY - notch.minY
        return [
            Surface(id: Self.leftPerch, y: y, minX: left - 84, maxX: left - 4, windowFrame: nil),
            Surface(id: Self.rightPerch, y: y, minX: right + 4, maxX: right + 84, windowFrame: nil),
        ]
    }

    private func distance(to surface: Surface) -> CGFloat {
        abs(surface.y - position.y) + (surface.contains(position.x) ? 0 : 50)
    }

    private func landing(from oldY: CGFloat, to newY: CGFloat, x: CGFloat) -> Surface? {
        surfaces
            .filter { !$0.isPerch && $0.y >= oldY - 1 && $0.y <= newY && $0.contains(x) }
            .min { $0.y < $1.y }
    }

    // MARK: Choices

    private func decide(now: CFTimeInterval) {
        guard let sprite, let surface = standing else { return }

        if finishingEasterEgg {
            finishingEasterEgg = false
            easterEggUntil = .distantPast
            sprite.morph(into: .clawd)
            decideAt = now + 1.2
            return
        }

        if surface.isPerch {
            decideOnPerch(surface, now: now)
            return
        }

        let roll = Double.random(in: 0..<1)
        if roll < 0.07 {
            headHome(now: now)
        } else if now >= nextApple, roll < 0.25 {
            nextApple = now + Double.random(in: 180...360)
            startDisguise(.apple, now: now)
        } else if now >= nextDisguise, roll < 0.35 {
            nextDisguise = now + Double.random(in: 45...90)
            var options: [RoamingSprite.Look] = [.cursor]
            if surface.isFloor { options.append(.folder) }
            if let frame = surface.windowFrame, surface.minX <= frame.minX + 2 { options.append(.trafficLight) }
            startDisguise(options.randomElement() ?? .cursor, now: now)
        } else if roll < 0.62 {
            walk(on: surface, toward: CGFloat.random(in: (surface.minX + 10)...(surface.maxX - 10)), now: now)
        } else if roll < 0.78, let target = jumpTarget() {
            let landingX = min(max(position.x + CGFloat.random(in: -60...60), target.minX + 12), target.maxX - 12)
            let to = CGPoint(x: landingX, y: target.y)
            let rise = max(position.y - to.y, 0)
            jump = Jump(from: position, to: to, target: target, start: now, duration: 0.55 + Double(rise) / 900, height: rise + 36)
            sprite.facingLeft = to.x < position.x
            sprite.setPose(.fall)
            standing = nil
            mode = .jumping
        } else if roll < 0.88 {
            walk(on: surface, toward: pointerLocation().x, now: now)
        } else {
            sprite.setPose(Bool.random() ? .sit : .stand)
            decideAt = now + Double.random(in: 3...7)
        }
    }

    private func walk(on surface: Surface, toward x: CGFloat, now: CFTimeInterval) {
        guard let sprite else { return }
        let target = min(max(x, surface.minX + 8), surface.maxX - 8)
        guard abs(target - position.x) > 12 else {
            decideAt = now + 1.5
            return
        }
        walkTarget = target
        direction = target > position.x ? 1 : -1
        sprite.facingLeft = direction < 0
        sprite.setPose(.walk)
        mode = .walking
    }

    /// Next to the notch Clawd looks around and shuffles a little, then hops off.
    private func decideOnPerch(_ perch: Surface, now: CFTimeInterval) {
        guard let sprite else { return }
        if now >= perchLeaveAt {
            direction = perch.id == Self.leftPerch ? -1 : 1
            sprite.facingLeft = direction < 0
            standing = nil
            fallSpeed = -280
            driftX = direction * 110
            mode = .falling
            sprite.setPose(.fall)
        } else if Bool.random() {
            walk(on: perch, toward: CGFloat.random(in: perch.minX...perch.maxX), now: now)
        } else {
            sprite.setPose([.sit, .stand, .happy].randomElement() ?? .stand)
            decideAt = now + Double.random(in: 1.5...3.5)
        }
    }

    /// Goes back up for a while: into the notch when it is on, otherwise onto the menu bar beside it.
    private func headHome(now: CFTimeInterval) {
        if notchPet?.isShowing == true {
            stayHomeUntil = Date().addingTimeInterval(Double.random(in: 15...40))
            goAway(animated: true)
        } else if let perch = surfaces.filter(\.isPerch).randomElement(), let sprite {
            sprite.vanish { [weak self] in
                guard let self, let sprite = self.sprite else { return }
                self.position = CGPoint(x: (perch.minX + perch.maxX) / 2, y: perch.y)
                self.standing = perch
                sprite.reset()
                self.perchLeaveAt = CACurrentMediaTime() + Double.random(in: 7...14)
                self.mode = .idle
                self.decideAt = CACurrentMediaTime() + 1
                self.place()
            }
            mode = .resting
        } else {
            decideAt = now + 2
        }
    }

    private func jumpTarget() -> Surface? {
        surfaces
            .filter { $0.id != standing?.id && !$0.isPerch }
            .filter { abs($0.y - position.y) < 260 && $0.y < screenSize.height }
            .filter { surface in
                let nearest = min(max(position.x, surface.minX), surface.maxX)
                return abs(nearest - position.x) < 140
            }
            .randomElement()
    }

    // MARK: Disguises

    private func startDisguise(_ look: RoamingSprite.Look, now: CFTimeInterval) {
        guard let sprite else { return }
        var windowID: Int?
        if look == .trafficLight {
            guard standing?.windowFrame != nil else { return }
            windowID = standing?.id
        }
        mode = .disguised
        disguise = Disguise(look: look, until: now + Double.random(in: 6...9), returnPoint: position, windowID: windowID)
        sprite.morph(into: look) { [weak self] in
            self?.updateDisguise(now: CACurrentMediaTime())
        }
    }

    private func updateDisguise(now: CFTimeInterval) {
        guard var disguise, let sprite else { return }

        switch disguise.look {
        case .apple:
            // Right on top of the Apple menu.
            position = CGPoint(x: 21, y: menuBarHeight() / 2 + sprite.size.height / 2)
        case .trafficLight:
            // Just past the green button, centered on the title bar.
            if let frame = surfaces.first(where: { $0.id == disguise.windowID })?.windowFrame {
                position = CGPoint(x: frame.minX + 80, y: frame.minY + 22)
                disguise.returnPoint = CGPoint(x: frame.minX + 40, y: frame.minY)
            } else {
                disguise.until = now
            }
        case .cursor:
            let pointer = pointerLocation()
            position.x += (pointer.x + 22 - position.x) * 0.12
            position.y += (pointer.y + 34 - position.y) * 0.12
            disguise.returnPoint = position
        case .folder, .clawd, .webSuit, .popStar:
            break
        }
        self.disguise = disguise

        guard now >= disguise.until, sprite.look == disguise.look else { return }
        self.disguise = nil
        let back = disguise.returnPoint
        mode = .jumping
        sprite.morph(into: .clawd) { [weak self] in
            guard let self else { return }
            self.position = back
            self.standing = nil
            self.fallSpeed = 0
            self.mode = .falling
            self.sprite?.setPose(.fall)
            self.place()
        }
    }

    // MARK: Easter eggs

    private func playEasterEgg(_ egg: ClaudeActivityWatcher.EasterEgg) {
        guard isEnabled, Date().timeIntervalSince(egg.date) < 60, let sprite, panel != nil,
              ![.swinging, .partying].contains(mode) else { return }

        easterEggUntil = Date().addingTimeInterval(40)
        disguise = nil
        jump = nil
        if mode == .away {
            notchPet?.setAway(true)
            sprite.reset()
            sprite.layer.isHidden = false
            displayLink?.isPaused = false
            let start = notchPet?.dropPoint ?? CGPoint(x: screenSize.width / 2, y: menuBarHeight() + 4)
            position = CGPoint(x: start.x, y: start.y + sprite.size.height + 40)
        }
        scanSurfaces()

        switch egg.kind {
        case .webSlinger:
            startSwinging()
        case .popStar:
            startParty()
        }
    }

    /// Suits up and swings across the screen on webs hung from the menu bar.
    private func startSwinging() {
        guard let sprite else { return }
        let now = CACurrentMediaTime()
        let length = min(240, (screenSize.height - menuBarHeight()) * 0.32)
        let angle: CGFloat = 0.85
        let heading: CGFloat = position.x < screenSize.width / 2 ? 1 : -1
        let startEdge = heading > 0 ? 50 : screenSize.width - 50
        let anchor = CGPoint(x: startEdge + heading * length * sin(angle), y: menuBarHeight() + 4)

        swing = Swing(direction: heading, anchor: anchor, length: length, angle: angle, start: now, zipFrom: position)
        standing = nil
        mode = .swinging
        sprite.facingLeft = heading < 0
        sprite.morph(into: .webSuit) { [weak self] in
            self?.sprite?.setPose(.fall)
        }
    }

    private func updateSwing(now: CFTimeInterval) {
        guard var swing, let sprite else { return }
        let reach = CGPoint(
            x: swing.anchor.x - swing.direction * swing.length * sin(swing.angle),
            y: swing.anchor.y + swing.length * cos(swing.angle)
        )
        var hand: CGPoint

        if let from = swing.zipFrom {
            // Pulled up along the first web to where the swing starts.
            let t = CGFloat(min((now - swing.start) / 0.7, 1))
            let eased = t * t * (3 - 2 * t)
            let fromHand = CGPoint(x: from.x, y: from.y - sprite.size.height)
            hand = CGPoint(x: fromHand.x + (reach.x - fromHand.x) * eased, y: fromHand.y + (reach.y - fromHand.y) * eased)
            if t >= 1 {
                swing.zipFrom = nil
                swing.start = now
            }
        } else {
            let t = CGFloat(min((now - swing.start) / 1.05, 1))
            let theta = -swing.angle * cos(.pi * t)
            hand = CGPoint(
                x: swing.anchor.x + swing.direction * swing.length * sin(theta),
                y: swing.anchor.y + swing.length * cos(theta)
            )
            tilt(-theta * swing.direction * 0.5)
            if t >= 1 {
                swing.count += 1
                let next = CGPoint(x: hand.x + swing.direction * swing.length * sin(swing.angle), y: swing.anchor.y)
                let offscreen = swing.direction > 0 ? next.x > screenSize.width - 30 : next.x < 30
                if offscreen || swing.count >= 7 {
                    // Let go and fly off the last swing.
                    self.swing = nil
                    web.path = nil
                    tilt(0)
                    position = CGPoint(x: hand.x, y: hand.y + sprite.size.height)
                    fallSpeed = -260
                    driftX = swing.direction * 240
                    finishingEasterEgg = true
                    mode = .falling
                    return
                }
                swing.anchor = next
                swing.start = now
            }
        }

        position = CGPoint(x: hand.x, y: hand.y + sprite.size.height)
        let path = CGMutablePath()
        path.move(to: swing.anchor)
        path.addLine(to: hand)
        for spoke in 0..<4 {
            let angle = CGFloat(spoke) * .pi / 4
            path.move(to: CGPoint(x: swing.anchor.x - cos(angle) * 5, y: swing.anchor.y - sin(angle) * 5))
            path.addLine(to: CGPoint(x: swing.anchor.x + cos(angle) * 5, y: swing.anchor.y + sin(angle) * 5))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        web.path = path
        CATransaction.commit()
        self.swing = swing
    }

    private func tilt(_ angle: CGFloat) {
        guard let sprite else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.layer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        CATransaction.commit()
    }

    /// A disco ball drops, the platinum hair and the bow come out, and it is paws up for a while.
    private func startParty() {
        guard let sprite else { return }
        if standing == nil {
            // Dance once he lands.
            partyPending = true
            fallSpeed = 0
            mode = .falling
            sprite.setPose(.fall)
        } else {
            beginParty()
        }
    }

    private func beginParty() {
        guard let sprite else { return }
        partyPending = false
        mode = .partying
        partyUntil = CACurrentMediaTime() + 10
        sprite.morph(into: .popStar) { [weak sprite] in
            sprite?.setPose(.dance)
        }
        dropDiscoBall(above: position)
        floatNotes()
    }

    private func finishParty(now: CFTimeInterval) {
        guard let sprite else { return }
        effects.sublayers?.forEach { layer in
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.toValue = 0
            fade.duration = 0.4
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            layer.add(fade, forKey: "fade")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.effects.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
        sprite.setPose(.stand)
        mode = .idle
        finishingEasterEgg = true
        decideAt = now + 0.3
    }

    private func dropDiscoBall(above point: CGPoint) {
        let top = menuBarHeight()
        let hang = min(max(point.y - top - 90, 60), 260)
        let x = point.x

        let string = CAShapeLayer()
        let stringPath = CGMutablePath()
        stringPath.move(to: CGPoint(x: x, y: top))
        stringPath.addLine(to: CGPoint(x: x, y: top + hang))
        string.path = stringPath
        string.strokeColor = NSColor(white: 0.8, alpha: 0.9).cgColor
        string.lineWidth = 1
        string.strokeEnd = 1
        effects.addSublayer(string)

        let radius: CGFloat = 16
        let ball = CAGradientLayer()
        ball.type = .radial
        ball.colors = [NSColor.white.cgColor, NSColor(white: 0.72, alpha: 1).cgColor, NSColor(white: 0.45, alpha: 1).cgColor]
        ball.locations = [0, 0.55, 1]
        ball.startPoint = CGPoint(x: 0.35, y: 0.3)
        ball.endPoint = CGPoint(x: 1, y: 1)
        ball.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        ball.cornerRadius = radius
        ball.masksToBounds = true
        ball.position = CGPoint(x: x, y: top + hang + radius)

        let grid = CAShapeLayer()
        let gridPath = CGMutablePath()
        for index in 1..<5 {
            let offset = CGFloat(index) * radius * 2 / 5
            gridPath.move(to: CGPoint(x: 0, y: offset))
            gridPath.addLine(to: CGPoint(x: radius * 2, y: offset))
            gridPath.move(to: CGPoint(x: offset, y: 0))
            gridPath.addLine(to: CGPoint(x: offset, y: radius * 2))
        }
        grid.path = gridPath
        grid.strokeColor = NSColor(white: 0.3, alpha: 0.5).cgColor
        grid.lineWidth = 0.6
        grid.frame = ball.bounds
        ball.addSublayer(grid)
        let spin = CABasicAnimation(keyPath: "transform.translation.x")
        spin.fromValue = 0
        spin.toValue = radius * 2 / 5
        spin.duration = 0.5
        spin.repeatCount = .infinity
        grid.add(spin, forKey: "spin")
        effects.addSublayer(ball)

        let drop = CABasicAnimation(keyPath: "transform.translation.y")
        drop.fromValue = -(hang + radius * 2)
        drop.toValue = 0
        drop.duration = 0.6
        drop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ball.add(drop, forKey: "drop")
        let reel = CABasicAnimation(keyPath: "strokeEnd")
        reel.fromValue = 0
        reel.toValue = 1
        reel.duration = 0.6
        reel.timingFunction = CAMediaTimingFunction(name: .easeOut)
        string.add(reel, forKey: "reel")

        // Colored spots of light sweeping around the dance floor.
        let colors: [NSColor] = [.systemPink, .systemTeal, .systemYellow, .systemPurple, .systemOrange, .systemBlue]
        for (index, color) in colors.enumerated() {
            let spot = CAShapeLayer()
            spot.path = CGPath(ellipseIn: CGRect(x: -5, y: -5, width: 10, height: 10), transform: nil)
            spot.fillColor = color.withAlphaComponent(0.55).cgColor
            let angle = CGFloat(index) / CGFloat(colors.count) * 2 * .pi
            let center = CGPoint(x: point.x, y: point.y - 20)
            spot.position = CGPoint(x: center.x + cos(angle) * 70, y: center.y + sin(angle) * 30)
            effects.addSublayer(spot)
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: center.x - 70, y: center.y - 30, width: 140, height: 60))
            let orbit = CAKeyframeAnimation(keyPath: "position")
            orbit.path = path
            orbit.duration = 3
            orbit.timeOffset = Double(index) / Double(colors.count) * 3
            orbit.repeatCount = .infinity
            orbit.calculationMode = .paced
            spot.add(orbit, forKey: "orbit")
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.3
            pulse.toValue = 1
            pulse.duration = 0.4
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            spot.add(pulse, forKey: "pulse")
        }
    }

    private func floatNotes() {
        for index in 0..<6 {
            let note = CATextLayer()
            note.string = index % 2 == 0 ? "♪" : "♫"
            note.fontSize = 14
            note.foregroundColor = NSColor(white: 1, alpha: 0.95).cgColor
            note.shadowColor = NSColor.black.cgColor
            note.shadowOpacity = 0.5
            note.shadowRadius = 1
            note.shadowOffset = .zero
            note.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            note.alignmentMode = .center
            note.bounds = CGRect(x: 0, y: 0, width: 16, height: 18)
            note.position = CGPoint(x: position.x + (index % 2 == 0 ? -26 : 26), y: position.y - 30)
            note.opacity = 0
            effects.addSublayer(note)

            let rise = CABasicAnimation(keyPath: "transform.translation")
            rise.fromValue = NSValue(size: .zero)
            rise.toValue = NSValue(size: CGSize(width: index % 2 == 0 ? -18 : 18, height: -50))
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.2, 0.7, 1]
            let group = CAAnimationGroup()
            group.animations = [rise, fade]
            group.duration = 1.6
            group.repeatCount = .infinity
            group.timeOffset = Double(index) * 0.27
            note.add(group, forKey: "float")
        }
    }

    // MARK: Pointer

    /// Resting the pointer on Clawd for a moment counts as petting him.
    private func watchPointer(now: CFTimeInterval) {
        guard let sprite, sprite.look == .clawd, [.idle, .walking].contains(mode) else {
            hoverSince = nil
            return
        }
        let pointer = pointerLocation()
        let frame = CGRect(x: position.x - sprite.size.width / 2, y: position.y - sprite.size.height, width: sprite.size.width, height: sprite.size.height)
            .insetBy(dx: -6, dy: -6)
        guard frame.contains(pointer) else {
            hoverSince = nil
            return
        }
        if hoverSince == nil { hoverSince = now }
        if let since = hoverSince, now - since > 0.5, now > pettedUntil + 4 {
            pettedUntil = now + 2
            hoverSince = nil
            sprite.setPose(.happy)
            mode = .idle
            decideAt = now + 2
        }
    }

    private func pointerLocation() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let origin = NSScreen.screens.first?.frame.origin ?? .zero
        return CGPoint(x: mouse.x - origin.x, y: screenSize.height - (mouse.y - origin.y))
    }

    private func menuBarHeight() -> CGFloat {
        guard let screen = NSScreen.screens.first else { return 25 }
        return max(screen.frame.maxY - screen.visibleFrame.maxY, 25)
    }
}

private final class FlippedLayerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
}
