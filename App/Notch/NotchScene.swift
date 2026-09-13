import AppKit
import QuartzCore

/// Clawd living under the notch. Everything is Core Animation, so the loops run in the
/// render server and the app stays idle between changes.
///
/// Coordinates are in pixel units of Clawd's sprite: x from the middle of the notch,
/// y down from the notch edge.
final class NotchSceneView: NSView {
    enum HideReason: Hashable {
        case pointer, fullscreen
    }

    static let unit: CGFloat = 2
    static let depth: CGFloat = 44

    private let u = NotchSceneView.unit
    private let stage = CALayer()
    private let slider = CALayer()
    private let rig = CALayer()
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private(set) var activity: PetActivity?
    private var hiddenReasons: Set<HideReason> = []
    private var swapping = false
    private var generation = 0
    private var idleTimer: Timer?

    init(size: CGSize, ceiling: CGFloat) {
        super.init(frame: CGRect(origin: .zero, size: size))
        let root = CALayer()
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true

        stage.frame = CGRect(x: 0, y: ceiling, width: size.width, height: size.height - ceiling)
        stage.masksToBounds = true
        root.addSublayer(stage)

        slider.frame = stage.bounds
        slider.setValue(-hiddenOffset, forKeyPath: "transform.translation.y")
        stage.addSublayer(slider)

        rig.bounds = stage.bounds
        rig.anchorPoint = CGPoint(x: 0.5, y: 0)
        rig.position = CGPoint(x: stage.bounds.midX, y: 0)
        slider.addSublayer(rig)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var hiddenOffset: CGFloat { stage.bounds.height + 2 }

    // MARK: Public

    /// Ducks behind the notch, changes outfit and drops back down.
    func show(_ next: PetActivity, animated: Bool = true) {
        guard next != activity else { return }
        activity = next
        swap(animated: animated) { [weak self] in self?.build(next) }
    }

    func setHidden(_ hidden: Bool, reason: HideReason) {
        let wasVisible = hiddenReasons.isEmpty
        if hidden {
            hiddenReasons.insert(reason)
        } else {
            hiddenReasons.remove(reason)
        }
        guard !swapping, hiddenReasons.isEmpty != wasVisible else { return }
        slide(hidden: !hiddenReasons.isEmpty, animated: true)
    }

    // MARK: Transitions

    private func swap(animated: Bool, build: @escaping () -> Void) {
        generation += 1
        let token = generation
        idleTimer?.invalidate()

        let finish = { [weak self] in
            guard let self, token == self.generation else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            build()
            CATransaction.commit()
            self.swapping = false
            if self.hiddenReasons.isEmpty {
                self.slide(hidden: false, animated: animated)
            }
            self.scheduleIdleBehavior()
        }

        // Only duck when Clawd is actually on screen, otherwise change right away.
        if animated, !reduceMotion, hiddenReasons.isEmpty {
            swapping = true
            slide(hidden: true, animated: true, completion: finish)
        } else {
            slide(hidden: true, animated: false)
            finish()
        }
    }

    private func slide(hidden: Bool, animated: Bool, completion: (() -> Void)? = nil) {
        let target = hidden ? -hiddenOffset : 0
        let from = (slider.presentation() ?? slider).value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion)
        slider.setValue(target, forKeyPath: "transform.translation.y")
        if animated && !reduceMotion {
            let animation: CABasicAnimation
            if hidden {
                animation = CABasicAnimation(keyPath: "transform.translation.y")
                animation.duration = 0.22
                animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
            } else {
                let spring = CASpringAnimation(keyPath: "transform.translation.y")
                spring.mass = 0.9
                spring.stiffness = 170
                spring.damping = 13
                spring.duration = spring.settlingDuration
                animation = spring
            }
            animation.fromValue = from
            animation.toValue = target
            slider.add(animation, forKey: "slide")
        }
        CATransaction.commit()
    }

    // MARK: Idle behavior

    private func scheduleIdleBehavior() {
        idleTimer?.invalidate()
        guard activity == .idle, !reduceMotion else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 20...40), repeats: false) { [weak self] _ in
            self?.performIdleBehavior()
        }
    }

    private func performIdleBehavior() {
        guard activity == .idle, hiddenReasons.isEmpty, !swapping else {
            scheduleIdleBehavior()
            return
        }
        let peeking = Bool.random()
        swap(animated: true) { [weak self] in
            if peeking { self?.peeking() } else { self?.waving(sparkles: false) }
        }
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + (peeking ? 5.2 : 3.4)) { [weak self] in
            guard let self, token == self.generation, self.activity == .idle else { return }
            self.swap(animated: true) { [weak self] in self?.build(.idle) }
        }
    }

    // MARK: Poses

    private func build(_ activity: PetActivity) {
        rig.sublayers?.forEach { $0.removeFromSuperlayer() }
        rig.removeAllAnimations()
        rig.transform = CATransform3DIdentity

        switch activity {
        case .idle: hanging(thinking: false)
        case .thinking: hanging(thinking: true)
        case .celebrating: waving(sparkles: true)
        case .building: scaffold(); builder()
        case .typing: scaffold(); typist()
        case .reading: scaffold(); reader()
        case .searching: scaffold(); searcher()
        case .sleeping: hammock()
        }
    }

    private func hanging(thinking: Bool) {
        let pet = makePet(at: CGPoint(x: -8, y: 2.5), eyes: .open, arms: .raised)
        rig.addSublayer(pet.group)
        let period = thinking ? 2.8 : 2.2
        loop(rig, sway("transform.rotation.z", from: -0.05, to: 0.05, duration: period))
        loop(pet.legs, sway("transform.rotation.z", from: 0.14, to: -0.14, duration: period, offset: 0.4))
        blink(pet.eyes, double: !thinking)

        if thinking {
            pet.eyes.position.x += 0.4 * u
            pet.eyes.position.y -= 0.4 * u
            let dots: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [(9.2, 5.4, 1.2), (11.6, 3.6, 1.6), (14.6, 2, 2.2)]
            for (index, dot) in dots.enumerated() {
                let layer = circle(center: CGPoint(x: dot.x, y: dot.y), diameter: dot.size, fill: .white, stroke: NSColor.black.withAlphaComponent(0.5), lineWidth: 0.4)
                rig.addSublayer(layer)
                loop(layer, keyframes("opacity", [0.25, 1, 0.25], times: [0, 0.5, 1], duration: 1.5, offset: Double(2 - index) * 0.25))
            }
        } else {
            glance(pet.eyes)
        }
    }

    private func waving(sparkles: Bool) {
        let pet = makePet(at: CGPoint(x: -8, y: 2.5), eyes: .happy, arms: .waving)
        rig.addSublayer(pet.group)
        loop(rig, sway("transform.rotation.z", from: 0.03, to: 0.09, duration: 1.4))
        loop(pet.rightArm, sway("transform.rotation.z", from: -0.55, to: 0.3, duration: 0.24))
        loop(pet.legs, sway("transform.rotation.z", from: 0.1, to: -0.1, duration: 1.4, offset: 0.3))

        guard sparkles else { return }
        let spots: [(x: CGFloat, y: CGFloat)] = [(-11.5, 5), (10.5, 2.2), (12.5, 9.5)]
        for (index, spot) in spots.enumerated() {
            let star = pixels([
                CGRect(x: spot.x - 0.25, y: spot.y - 1, width: 0.5, height: 2),
                CGRect(x: spot.x - 1, y: spot.y - 0.25, width: 2, height: 0.5),
            ], Colors.spark, pivot: CGPoint(x: spot.x, y: spot.y))
            star.opacity = 0
            rig.addSublayer(star)
            let offset = Double(index) * 0.4
            loop(star, keyframes("transform.scale", [0.2, 1.2, 0.2], times: [0, 0.4, 1], duration: 1.2, offset: offset))
            loop(star, keyframes("opacity", [0, 1, 0], times: [0, 0.4, 1], duration: 1.2, offset: offset))
        }
    }

    /// Hangs upside down from behind the notch, looks around and pulls back up.
    private func peeking() {
        let peeker = group()
        let flipped = group(pivot: CGPoint(x: 0, y: 1))
        flipped.transform = CATransform3DMakeScale(1, -1, 1)
        peeker.addSublayer(flipped)
        let pet = makePet(at: CGPoint(x: -8, y: -4), eyes: .open, arms: .sides, in: flipped)
        rig.addSublayer(peeker)
        pet.eyes.position.y += 0.3 * u

        let hidden = -7 * u
        loop(peeker, keyframes(
            "transform.translation.y", [hidden, 0, 0, hidden],
            times: [0, 0.2, 0.8, 1],
            duration: 5,
            curves: [.easeOut, .linear, .easeIn]
        ), repeats: false)
        loop(pet.eyes, keyframes(
            "transform.translation.x", [0, 0, -0.6 * u, -0.6 * u, 0.6 * u, 0.6 * u, 0],
            times: [0, 0.22, 0.3, 0.45, 0.55, 0.7, 0.8],
            duration: 5,
            curves: [.linear, .easeInEaseOut, .linear, .easeInEaseOut, .linear, .easeInEaseOut]
        ), repeats: false)
    }

    private func scaffold() {
        rig.addSublayer(pixels([
            CGRect(x: -11.25, y: 0, width: 0.5, height: 15),
            CGRect(x: 10.75, y: 0, width: 0.5, height: 15),
        ], Colors.rope))
        rig.addSublayer(pixels([CGRect(x: -12.5, y: 15, width: 25, height: 1.6)], Colors.wood))
        rig.addSublayer(pixels([CGRect(x: -12.5, y: 15, width: 25, height: 0.45)], Colors.woodLight))
        loop(rig, sway("transform.rotation.z", from: -0.02, to: 0.02, duration: 3.2))
    }

    private func builder() {
        let origin = CGPoint(x: -8, y: 5)
        let pet = makePet(at: origin, eyes: .open, arms: .holding)
        rig.addSublayer(pet.group)

        pet.group.addSublayer(pixels([
            CGRect(x: -3, y: 3, width: 6, height: 1),
            CGRect(x: -4, y: 3.9, width: 8, height: 1.2),
            CGRect(x: -5.5, y: 4.9, width: 11, height: 0.7),
        ], Colors.hat))
        pet.group.addSublayer(pixels([CGRect(x: -0.5, y: 3, width: 1, height: 2.1)], Colors.hatStripe))

        let hand = CGPoint(x: origin.x + 14.75, y: origin.y + 1.5)
        let hammer = group(pivot: hand)
        hammer.addSublayer(pixels([CGRect(x: hand.x - 0.4, y: hand.y - 4.6, width: 0.8, height: 5.3)], Colors.handle))
        hammer.addSublayer(pixels([CGRect(x: hand.x - 1.8, y: hand.y - 6.5, width: 3.6, height: 2)], Colors.steel))
        hammer.addSublayer(pixels([CGRect(x: hand.x - 1.8, y: hand.y - 6.5, width: 3.6, height: 0.5)], Colors.steelLight))
        pet.group.addSublayer(hammer)

        let swing = 1.1
        let strike = 0.48
        loop(hammer, keyframes(
            "transform.rotation.z", [0.85, 0.85, -0.03, 0.14, 0.85],
            times: [0, 0.34, strike, 0.56, 1],
            duration: swing,
            curves: [.linear, .easeIn, .easeOut, .easeInEaseOut]
        ))
        loop(pet.group, keyframes(
            "transform.translation.y", [0, 0, 0.35 * u, 0, 0],
            times: [0, strike, strike + 0.05, 0.64, 1],
            duration: swing
        ))

        let bursts: [(dx: CGFloat, dy: CGFloat)] = [(-2.4, 1.5), (0.2, 2.6), (2.6, 1.3)]
        for burst in bursts {
            let spark = pixels([CGRect(x: hand.x - 0.4, y: 0.2, width: 0.8, height: 0.8)], Colors.spark)
            spark.opacity = 0
            rig.addSublayer(spark)
            loop(spark, keyframes("opacity", [0, 0, 1, 0, 0], times: [0, strike, strike + 0.01, strike + 0.22, 1], duration: swing))
            loop(spark, keyframes(
                "transform.translation",
                [CGSize.zero, .zero, CGSize(width: burst.dx * u, height: burst.dy * u), CGSize(width: burst.dx * u, height: burst.dy * u)].map { NSValue(size: $0) },
                times: [0, strike, strike + 0.22, 1],
                duration: swing,
                curves: [.linear, .easeOut, .linear]
            ))
        }

        pet.eyes.position.x += 0.35 * u
        pet.eyes.position.y -= 0.35 * u
        blink(pet.eyes, double: false)
    }

    private func typist() {
        let pet = makePet(at: CGPoint(x: -8, y: 5), eyes: .open, arms: .sides)
        rig.addSublayer(pet.group)

        loop(pet.leftArm, keyframes("transform.translation.y", [0, -0.9 * u, 0], times: [0, 0.5, 1], duration: 0.3))
        loop(pet.rightArm, keyframes("transform.translation.y", [0, -0.9 * u, 0], times: [0, 0.5, 1], duration: 0.3, offset: 0.15))

        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [Colors.screenGlow.withAlphaComponent(0.28).cgColor, Colors.screenGlow.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 1)
        glow.endPoint = CGPoint(x: 1, y: 0)
        glow.frame = rect(CGRect(x: -7, y: 4, width: 14, height: 6))
        rig.addSublayer(glow)
        loop(glow, keyframes("opacity", [0.7, 1, 0.8, 0.95, 0.7], times: [0, 0.3, 0.5, 0.8, 1], duration: 3.2))

        rig.addSublayer(pixels([CGRect(x: -6.5, y: 9.5, width: 13, height: 4.8)], Colors.lid))
        rig.addSublayer(pixels([CGRect(x: -6.5, y: 9.5, width: 13, height: 0.45)], Colors.lidLight))
        rig.addSublayer(pixels([CGRect(x: -7.5, y: 14.3, width: 15, height: 0.7)], Colors.deck))

        pet.eyes.position.y += 0.5 * u
        glance(pet.eyes, reach: 0.3, duration: 7)
        blink(pet.eyes, double: false)
    }

    private func reader() {
        let pet = makePet(at: CGPoint(x: -8, y: 5), eyes: .open, arms: .sides)
        rig.addSublayer(pet.group)

        let book = group()
        book.addSublayer(pixels([CGRect(x: -6.9, y: 8.6, width: 13.8, height: 5.6)], Colors.bookCover))
        book.addSublayer(pixels([
            CGRect(x: -6.4, y: 8.9, width: 6.1, height: 5),
            CGRect(x: 0.3, y: 8.9, width: 6.1, height: 5),
        ], Colors.page))
        book.addSublayer(pixels([
            CGRect(x: -5.7, y: 9.9, width: 4.7, height: 0.35), CGRect(x: -5.7, y: 10.9, width: 4.2, height: 0.35),
            CGRect(x: -5.7, y: 11.9, width: 4.7, height: 0.35), CGRect(x: -5.7, y: 12.9, width: 3.4, height: 0.35),
            CGRect(x: 1, y: 9.9, width: 4.5, height: 0.35), CGRect(x: 1, y: 10.9, width: 4.8, height: 0.35),
            CGRect(x: 1, y: 11.9, width: 3.8, height: 0.35), CGRect(x: 1, y: 12.9, width: 4.6, height: 0.35),
        ], Colors.ink))
        let page = pixels([CGRect(x: 0.3, y: 8.9, width: 6.1, height: 5)], Colors.pageShade, pivot: CGPoint(x: 0, y: 11.4))
        page.opacity = 0
        book.addSublayer(page)
        rig.addSublayer(book)

        loop(page, keyframes("transform.scale.x", [1, 1, -1, -1], times: [0, 0.82, 0.93, 1], duration: 6, curves: [.linear, .easeInEaseOut, .linear]))
        loop(page, keyframes("opacity", [0, 0, 1, 1, 0, 0], times: [0, 0.819, 0.82, 0.93, 0.931, 1], duration: 6))
        loop(book, sway("transform.translation.y", from: 0, to: 0.25 * u, duration: 1.6))

        pet.eyes.position.y += 0.45 * u
        loop(pet.eyes, keyframes("transform.translation.x", [-0.5 * u, 0.5 * u, -0.5 * u], times: [0, 0.82, 1], duration: 1.9, curves: [.linear, .easeInEaseOut]))
        blink(pet.eyes, double: false)
    }

    private func searcher() {
        let pet = makePet(at: CGPoint(x: -8, y: 5), eyes: .open, arms: .sides)
        rig.addSublayer(pet.group)

        let center = CGPoint(x: 1.5, y: 10.4)
        let glass = group(pivot: center)
        let handle = CAShapeLayer()
        handle.frame = rig.bounds
        let path = CGMutablePath()
        path.move(to: point(center.x + 2.1, center.y + 1.5))
        path.addLine(to: point(center.x + 4.6, center.y + 4))
        handle.path = path
        handle.strokeColor = Colors.handle.cgColor
        handle.lineWidth = 1.1 * u
        handle.lineCap = .round
        glass.addSublayer(handle)
        glass.addSublayer(circle(center: center, diameter: 5.6, fill: Colors.lens.withAlphaComponent(0.35), stroke: Colors.steel, lineWidth: 0.9))
        glass.addSublayer(pixels([CGRect(x: center.x - 1.5, y: center.y - 1.7, width: 0.9, height: 0.9)], NSColor.white.withAlphaComponent(0.85)))
        rig.addSublayer(glass)

        let route: [(x: CGFloat, y: CGFloat)] = [(0, 0), (2.5, -1.2), (4.2, 0.2), (2.5, 1.4), (0, 0.2), (-2.5, -1.2), (-4.4, 0.2), (-2.5, 1.4), (0, 0)]
        let times = route.indices.map { Double($0) / Double(route.count - 1) }
        loop(glass, keyframes(
            "transform.translation",
            route.map { NSValue(size: CGSize(width: $0.x * u, height: $0.y * u)) },
            times: times,
            duration: 6.4,
            mode: .cubic
        ))
        loop(pet.eyes, keyframes("transform.translation.x", route.map { $0.x * 0.14 * u }, times: times, duration: 6.4, mode: .cubic))
        blink(pet.eyes, double: false)
    }

    private func hammock() {
        let ropes = CAShapeLayer()
        ropes.frame = rig.bounds
        let ropePath = CGMutablePath()
        ropePath.move(to: point(-13, 0))
        ropePath.addLine(to: point(-11.5, 6.5))
        ropePath.move(to: point(13, 0))
        ropePath.addLine(to: point(11.5, 6.5))
        ropes.path = ropePath
        ropes.strokeColor = Colors.rope.cgColor
        ropes.lineWidth = 0.5 * u
        rig.addSublayer(ropes)

        let pet = makePet(at: CGPoint(x: -8, y: 4.6), eyes: .closed, arms: .sides)
        pet.legs.isHidden = true
        rig.addSublayer(pet.group)
        loop(pet.group, sway("transform.translation.y", from: 0, to: -0.3 * u, duration: 2.2))

        let fabric = CAShapeLayer()
        fabric.frame = rig.bounds
        let fabricPath = CGMutablePath()
        fabricPath.move(to: point(-11.5, 6.5))
        fabricPath.addQuadCurve(to: point(11.5, 6.5), control: point(0, 21))
        fabricPath.addQuadCurve(to: point(-11.5, 6.5), control: point(0, 13.4))
        fabric.path = fabricPath
        fabric.fillColor = Colors.fabric.cgColor
        fabric.strokeColor = NSColor.black.withAlphaComponent(0.18).cgColor
        fabric.lineWidth = 0.6
        rig.addSublayer(fabric)

        let stripe = CAShapeLayer()
        stripe.frame = rig.bounds
        let stripePath = CGMutablePath()
        stripePath.move(to: point(-11.5, 6.5))
        stripePath.addQuadCurve(to: point(11.5, 6.5), control: point(0, 15.4))
        stripePath.addQuadCurve(to: point(-11.5, 6.5), control: point(0, 13.4))
        stripe.path = stripePath
        stripe.fillColor = Colors.clay.cgColor
        rig.addSublayer(stripe)

        loop(rig, sway("transform.rotation.z", from: -0.035, to: 0.035, duration: 3))

        for index in 0..<3 {
            let side = CGFloat(index) * 0.1 + 0.36
            let z = pixels(Sprite.z.map {
                CGRect(x: 5 + $0.minX * side, y: 3.2 + $0.minY * side, width: $0.width * side, height: $0.height * side)
            }, NSColor.white, pivot: CGPoint(x: 5 + 2.5 * side, y: 3.2 + 2.5 * side))
            z.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
            z.lineWidth = 0.5
            z.opacity = 0
            rig.addSublayer(z)
            let offset = Double(2 - index) * 1.1
            loop(z, keyframes(
                "transform.translation",
                [NSValue(size: .zero), NSValue(size: CGSize(width: 6.5 * u, height: -2.4 * u))],
                times: [0, 1],
                duration: 3.3,
                offset: offset
            ))
            loop(z, keyframes("opacity", [0, 1, 1, 0], times: [0, 0.2, 0.65, 1], duration: 3.3, offset: offset))
            loop(z, keyframes("transform.scale", [0.7, 1.15], times: [0, 1], duration: 3.3, offset: offset))
        }
    }

    // MARK: Clawd

    private enum EyeStyle {
        case open, closed, happy
    }

    private enum ArmStyle {
        /// The usual arms on each side.
        case sides
        /// Both hands up, holding on to the notch.
        case raised
        /// Left hand on the notch, right hand waving.
        case waving
        /// Right hand up, holding a tool.
        case holding
    }

    private struct Pet {
        let group: CALayer
        let eyes: CAShapeLayer
        let leftArm: CAShapeLayer
        let rightArm: CAShapeLayer
        let legs: CAShapeLayer
    }

    private func makePet(at origin: CGPoint, eyes style: EyeStyle, arms: ArmStyle, in parent: CALayer? = nil) -> Pet {
        let group = parent ?? self.group()
        func shift(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: origin.x, dy: origin.y) }
        let ceiling = -origin.y

        let legs = pixels(
            Sprite.legColumns.map { shift(CGRect(x: $0, y: 7.5, width: 1, height: 2.5)) },
            Colors.clay,
            pivot: CGPoint(x: origin.x + 8, y: origin.y + 7.5)
        )

        let leftRect: CGRect
        let rightRect: CGRect
        var rightPivot: CGPoint?
        switch arms {
        case .sides:
            leftRect = Sprite.leftArm
            rightRect = Sprite.rightArm
        case .raised:
            leftRect = CGRect(x: 0.5, y: ceiling, width: 1.5, height: 6 - ceiling)
            rightRect = CGRect(x: 14, y: ceiling, width: 1.5, height: 6 - ceiling)
        case .waving:
            leftRect = CGRect(x: 0.5, y: ceiling, width: 1.5, height: 6 - ceiling)
            rightRect = CGRect(x: 14, y: 0.5, width: 1.5, height: 5.5)
            rightPivot = CGPoint(x: origin.x + 14.75, y: origin.y + 6)
        case .holding:
            leftRect = Sprite.leftArm
            rightRect = CGRect(x: 14, y: 1.5, width: 1.5, height: 4.5)
        }
        let leftArm = pixels([shift(leftRect)], Colors.clay)
        let rightArm = pixels([shift(rightRect)], Colors.clay, pivot: rightPivot)

        let core = pixels([shift(Sprite.core)], Colors.clay)

        let eyeRects: [CGRect]
        switch style {
        case .open:
            eyeRects = [CGRect(x: 4, y: 2, width: 1, height: 2), CGRect(x: 11, y: 2, width: 1, height: 2)]
        case .closed:
            eyeRects = [CGRect(x: 3.5, y: 3, width: 2, height: 0.5), CGRect(x: 10.5, y: 3, width: 2, height: 0.5)]
        case .happy:
            eyeRects = [4, 11].flatMap { (column: CGFloat) in [
                CGRect(x: column - 0.5, y: 2.75, width: 0.5, height: 1),
                CGRect(x: column, y: 2.25, width: 1, height: 0.5),
                CGRect(x: column + 1, y: 2.75, width: 0.5, height: 1),
            ] }
        }
        let eyes = pixels(eyeRects.map(shift), Colors.eye, pivot: CGPoint(x: origin.x + 8, y: origin.y + 3))

        for layer in [legs, leftArm, rightArm, core, eyes] {
            group.addSublayer(layer)
        }
        return Pet(group: group, eyes: eyes, leftArm: leftArm, rightArm: rightArm, legs: legs)
    }

    private func blink(_ eyes: CALayer, double: Bool) {
        if double {
            loop(eyes, keyframes("transform.scale.y", [1, 1, 0.1, 1, 1, 0.1, 1, 1], times: [0, 0.84, 0.865, 0.89, 0.92, 0.945, 0.97, 1], duration: 5.6))
        } else {
            loop(eyes, keyframes("transform.scale.y", [1, 1, 0.1, 1, 1], times: [0, 0.9, 0.93, 0.96, 1], duration: 4.4))
        }
    }

    private func glance(_ eyes: CALayer, reach: CGFloat = 0.6, duration: Double = 9) {
        let r = reach * u
        loop(eyes, keyframes(
            "transform.translation.x", [0, 0, r, r, 0, 0, -r, -r, 0, 0],
            times: [0, 0.2, 0.26, 0.45, 0.51, 0.66, 0.72, 0.9, 0.96, 1],
            duration: duration,
            curves: Array(repeating: .easeInEaseOut, count: 9)
        ))
    }

    // MARK: Layers

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rig.bounds.midX + x * u, y: y * u)
    }

    private func rect(_ rect: CGRect) -> CGRect {
        CGRect(x: rig.bounds.midX + rect.minX * u, y: rect.minY * u, width: rect.width * u, height: rect.height * u)
    }

    /// A container using the same coordinates as the rig, turning around `pivot`.
    private func group(pivot: CGPoint = .zero) -> CALayer {
        let layer = CALayer()
        let anchor = point(pivot.x, pivot.y)
        layer.bounds = rig.bounds
        layer.anchorPoint = CGPoint(x: anchor.x / rig.bounds.width, y: anchor.y / rig.bounds.height)
        layer.position = anchor
        return layer
    }

    /// Pixel rects in units, drawn in one layer that turns and scales around `pivot`.
    private func pixels(_ rects: [CGRect], _ color: NSColor, pivot: CGPoint? = nil) -> CAShapeLayer {
        let frames = rects.map(rect)
        let box = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        let anchor = pivot.map { point($0.x, $0.y) } ?? CGPoint(x: box.midX, y: box.midY)

        let layer = CAShapeLayer()
        layer.bounds = CGRect(origin: .zero, size: box.size)
        layer.anchorPoint = CGPoint(x: (anchor.x - box.minX) / box.width, y: (anchor.y - box.minY) / box.height)
        layer.position = anchor
        let path = CGMutablePath()
        for frame in frames {
            path.addRect(frame.offsetBy(dx: -box.minX, dy: -box.minY))
        }
        layer.path = path
        layer.fillColor = color.cgColor
        return layer
    }

    private func circle(center: CGPoint, diameter: CGFloat, fill: NSColor, stroke: NSColor, lineWidth: CGFloat = 0.3) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let size = diameter * u
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layer.position = point(center.x, center.y)
        layer.path = CGPath(ellipseIn: layer.bounds, transform: nil)
        layer.fillColor = fill.cgColor
        layer.strokeColor = stroke.cgColor
        layer.lineWidth = lineWidth * u
        return layer
    }

    // MARK: Animation

    private func loop(_ layer: CALayer, _ animation: CAAnimation, repeats: Bool = true) {
        guard !reduceMotion else { return }
        if !repeats {
            animation.repeatCount = 1
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        layer.add(animation, forKey: (animation as? CAPropertyAnimation)?.keyPath)
    }

    private func keyframes(
        _ keyPath: String,
        _ values: [Any],
        times: [Double],
        duration: Double,
        curves: [CAMediaTimingFunctionName]? = nil,
        offset: Double = 0,
        mode: CAAnimationCalculationMode = .linear
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.calculationMode = mode
        animation.timeOffset = offset
        if let curves {
            animation.timingFunctions = curves.map { CAMediaTimingFunction(name: $0) }
        }
        return animation
    }

    private func sway(_ keyPath: String, from: CGFloat, to: CGFloat, duration: Double, offset: Double = 0) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timeOffset = offset
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }
}

private enum Colors {
    static let clay = NSColor(srgbRed: 215 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
    static let eye = NSColor.black
    static let rope = NSColor(srgbRed: 0.56, green: 0.54, blue: 0.51, alpha: 1)
    static let wood = NSColor(srgbRed: 0.62, green: 0.43, blue: 0.25, alpha: 1)
    static let woodLight = NSColor(srgbRed: 0.76, green: 0.55, blue: 0.33, alpha: 1)
    static let hat = NSColor(srgbRed: 0.96, green: 0.76, blue: 0.13, alpha: 1)
    static let hatStripe = NSColor(srgbRed: 0.85, green: 0.63, blue: 0.08, alpha: 1)
    static let handle = NSColor(srgbRed: 0.48, green: 0.32, blue: 0.19, alpha: 1)
    static let steel = NSColor(srgbRed: 0.6, green: 0.64, blue: 0.68, alpha: 1)
    static let steelLight = NSColor(srgbRed: 0.78, green: 0.81, blue: 0.84, alpha: 1)
    static let spark = NSColor(srgbRed: 1, green: 0.84, blue: 0.3, alpha: 1)
    static let screenGlow = NSColor(srgbRed: 0.62, green: 0.85, blue: 1, alpha: 1)
    static let lid = NSColor(srgbRed: 0.79, green: 0.81, blue: 0.84, alpha: 1)
    static let lidLight = NSColor(srgbRed: 0.9, green: 0.91, blue: 0.93, alpha: 1)
    static let deck = NSColor(srgbRed: 0.66, green: 0.69, blue: 0.73, alpha: 1)
    static let bookCover = NSColor(srgbRed: 0.24, green: 0.43, blue: 0.71, alpha: 1)
    static let page = NSColor(srgbRed: 0.96, green: 0.93, blue: 0.88, alpha: 1)
    static let pageShade = NSColor(srgbRed: 0.9, green: 0.86, blue: 0.79, alpha: 1)
    static let ink = NSColor(srgbRed: 0.72, green: 0.68, blue: 0.62, alpha: 1)
    static let lens = NSColor(srgbRed: 0.6, green: 0.84, blue: 1, alpha: 1)
    static let fabric = NSColor(srgbRed: 0.94, green: 0.9, blue: 0.83, alpha: 1)
}
