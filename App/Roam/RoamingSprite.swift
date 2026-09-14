import AppKit
import QuartzCore

/// Clawd walking around the desktop, and the things he likes to pretend to be.
/// The layer is anchored at his feet, so moving it moves the point he stands on.
final class RoamingSprite {
    enum Look: Equatable {
        case clawd, apple, folder, trafficLight
        /// Dressed up for the easter eggs, still Clawd underneath.
        case webSuit, popStar

        var hasBody: Bool {
            self == .clawd || self == .webSuit || self == .popStar
        }
    }

    enum Pose: Equatable {
        case stand, walk, fall, sit, sleep, happy, work, dance
    }

    let layer = CALayer()
    private let flipper = CALayer()
    private let squasher = CALayer()
    private let content = CALayer()
    private let extras = CALayer()
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private(set) var look: Look = .clawd
    private(set) var pose: Pose = .stand
    private var eyes: CAShapeLayer?
    private var leftArm: CALayer?
    private var rightArm: CALayer?
    private var legsA: CALayer?
    private var legsB: CALayer?
    /// Rows added above Clawd's head for hats and hair.
    private var bodyTop: CGFloat = 0

    var facingLeft = false {
        didSet {
            guard facingLeft != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            flipper.transform = CATransform3DMakeScale(facingLeft ? -1 : 1, 1, 1)
            CATransaction.commit()
        }
    }

    var size: CGSize { layer.bounds.size }

    init() {
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        for sublayer in [flipper, squasher, content] {
            sublayer.anchorPoint = CGPoint(x: 0.5, y: 1)
        }
        layer.addSublayer(flipper)
        flipper.addSublayer(squasher)
        squasher.addSublayer(content)
        layer.addSublayer(extras)
        build(.clawd)
    }

    // MARK: Changing

    func setPose(_ next: Pose) {
        guard look.hasBody, next != pose else { return }
        pose = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyPose()
        CATransaction.commit()
    }

    /// Shrinks into a little puff of dust and comes back as something else.
    func morph(into next: Look, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard next != look else {
            completion?()
            return
        }
        if animated { puff() }
        guard animated, !reduceMotion else {
            build(next)
            completion?()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.build(next)
            CATransaction.commit()
            let grow = CASpringAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.2
            grow.toValue = 1
            grow.damping = 10
            grow.stiffness = 220
            grow.duration = grow.settlingDuration
            self.squasher.add(grow, forKey: "grow")
            completion?()
        }
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.2
        shrink.duration = 0.13
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        squasher.add(shrink, forKey: "grow")
        CATransaction.commit()
    }

    /// Back to plain Clawd right away, used when he comes out of the notch.
    func reset() {
        squasher.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if look != .clawd { build(.clawd) }
        pose = .stand
        applyPose()
        CATransaction.commit()
    }

    /// Disappears in a puff of dust.
    func vanish(completion: @escaping () -> Void) {
        puff()
        guard !reduceMotion else {
            completion()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.05
        shrink.duration = 0.16
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        squasher.add(shrink, forKey: "grow")
        CATransaction.commit()
    }

    func land() {
        guard !reduceMotion else { return }
        let x = keyframes("transform.scale.x", [1.25, 0.94, 1], times: [0, 0.45, 1], duration: 0.3)
        let y = keyframes("transform.scale.y", [0.72, 1.08, 1], times: [0, 0.45, 1], duration: 0.3)
        x.repeatCount = 1
        y.repeatCount = 1
        squasher.add(x, forKey: "landX")
        squasher.add(y, forKey: "landY")
    }

    /// Little stars around Clawd when Claude finishes something.
    func sparkle() {
        let spots: [CGPoint] = [CGPoint(x: -6, y: -8), CGPoint(x: size.width + 4, y: -14), CGPoint(x: size.width + 8, y: 6), CGPoint(x: -10, y: 8)]
        for (index, spot) in spots.enumerated() {
            let star = CAShapeLayer()
            let path = CGMutablePath()
            path.addRect(CGRect(x: -0.75, y: -3, width: 1.5, height: 6))
            path.addRect(CGRect(x: -3, y: -0.75, width: 6, height: 1.5))
            star.path = path
            star.fillColor = SpriteColors.spark.cgColor
            star.position = spot
            star.opacity = 0
            extras.addSublayer(star)
            let delay = CACurrentMediaTime() + Double(index) * 0.12
            let pop = keyframes("transform.scale", [0.2, 1.4, 0.2], times: [0, 0.4, 1], duration: 0.9)
            let fade = keyframes("opacity", [0, 1, 0], times: [0, 0.35, 1], duration: 0.9)
            for animation in [pop, fade] {
                animation.repeatCount = 2
                animation.beginTime = delay
            }
            star.add(pop, forKey: "pop")
            star.add(fade, forKey: "fade")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { star.removeFromSuperlayer() }
        }
    }

    // MARK: Building

    private func build(_ next: Look) {
        look = next
        content.sublayers?.forEach { $0.removeFromSuperlayer() }
        content.removeAllAnimations()
        extras.sublayers?.forEach { $0.removeFromSuperlayer() }
        eyes = nil
        leftArm = nil
        rightArm = nil
        legsA = nil
        legsB = nil
        bodyTop = 0

        let size: CGSize
        switch next {
        case .clawd, .webSuit, .popStar: size = buildBody(next)
        case .apple: size = buildApple()
        case .folder: size = buildFolder()
        case .trafficLight: size = buildTrafficLight()
        }

        let bounds = CGRect(origin: .zero, size: size)
        for sublayer in [layer, flipper, squasher, content, extras] {
            sublayer.bounds = bounds
        }
        for sublayer in [flipper, squasher, content] {
            sublayer.position = CGPoint(x: size.width / 2, y: size.height)
        }
        extras.position = CGPoint(x: size.width / 2, y: size.height / 2)

        if next.hasBody {
            applyPose()
        } else if let eyes {
            blink(eyes)
        }
    }

    private func buildBody(_ kind: Look) -> CGSize {
        let u: CGFloat = 2.5
        let top: CGFloat = kind == .popStar ? 4.5 : 0
        bodyTop = top
        func shift(_ rects: [CGRect]) -> [CGRect] { rects.map { $0.offsetBy(dx: 0, dy: top) } }

        let suit = kind == .webSuit
        let skin = suit ? SpriteColors.suitRed : SpriteColors.clay
        let limbs = suit ? SpriteColors.suitBlue : SpriteColors.clay

        let core = pixels(shift([CGRect(x: 2, y: 0, width: 12, height: 8)]), skin, unit: u)
        let left = pixels(shift([CGRect(x: 0, y: 4, width: 2, height: 2)]), limbs, unit: u)
        let right = pixels(shift([CGRect(x: 14, y: 4, width: 2, height: 2)]), limbs, unit: u)
        let legs1 = pixels(shift([CGRect(x: 3, y: 7.5, width: 1, height: 2.5), CGRect(x: 10, y: 7.5, width: 1, height: 2.5)]), limbs, unit: u)
        let legs2 = pixels(shift([CGRect(x: 5, y: 7.5, width: 1, height: 2.5), CGRect(x: 12, y: 7.5, width: 1, height: 2.5)]), limbs, unit: u)
        for part in [legs1, legs2, left, right, core] {
            content.addSublayer(part)
        }
        leftArm = left
        rightArm = right
        legsA = legs1
        legsB = legs2

        switch kind {
        case .webSuit:
            content.addSublayer(pixels(shift([CGRect(x: 2, y: 5, width: 2, height: 3), CGRect(x: 12, y: 5, width: 2, height: 3)]), SpriteColors.suitBlue, unit: u))
            let web = CAShapeLayer()
            let path = CGMutablePath()
            for x: CGFloat in [5, 8, 11] {
                path.move(to: CGPoint(x: x * u, y: 0))
                path.addLine(to: CGPoint(x: x * u, y: 8 * u))
            }
            for y: CGFloat in [2.5, 5.5] {
                path.move(to: CGPoint(x: 2 * u, y: y * u))
                path.addLine(to: CGPoint(x: 14 * u, y: y * u))
            }
            web.path = path
            web.strokeColor = SpriteColors.suitLine.cgColor
            web.lineWidth = 0.6
            web.frame = CGRect(x: 0, y: 0, width: 16 * u, height: 10 * u)
            content.addSublayer(web)

            let lenses = CAShapeLayer()
            let lensPath = CGMutablePath()
            lensPath.addEllipse(in: CGRect(x: 3 * u, y: 1.4 * u, width: 3.2 * u, height: 2.6 * u))
            lensPath.addEllipse(in: CGRect(x: 9.8 * u, y: 1.4 * u, width: 3.2 * u, height: 2.6 * u))
            lenses.path = lensPath
            lenses.fillColor = NSColor.white.cgColor
            lenses.strokeColor = NSColor.black.cgColor
            lenses.lineWidth = 1.2
            lenses.bounds = CGRect(x: 0, y: 0, width: 16 * u, height: 10 * u)
            lenses.anchorPoint = CGPoint(x: 0.5, y: 0.27)
            lenses.position = CGPoint(x: 8 * u, y: 2.7 * u)
            content.addSublayer(lenses)
            eyes = lenses

        case .popStar:
            // Platinum hair with the famous bow, and dark glasses.
            content.addSublayer(pixels([
                CGRect(x: 1.5, y: 2.5, width: 13, height: 2.5),
                CGRect(x: 1, y: 4, width: 2.2, height: 4.5), CGRect(x: 12.8, y: 4, width: 2.2, height: 4.5),
            ], SpriteColors.hair, unit: u))
            content.addSublayer(pixels([
                CGRect(x: 4.5, y: 0, width: 3, height: 2.5), CGRect(x: 8.5, y: 0, width: 3, height: 2.5),
                CGRect(x: 7.2, y: 0.7, width: 1.6, height: 1.6),
            ], SpriteColors.hairShade, unit: u))
            content.addSublayer(pixels(shift([
                CGRect(x: 3.4, y: 1.7, width: 3.8, height: 2), CGRect(x: 8.8, y: 1.7, width: 3.8, height: 2),
                CGRect(x: 7.2, y: 2.1, width: 1.6, height: 0.5),
            ]), .black, unit: u))
            content.addSublayer(pixels(shift([
                CGRect(x: 3.9, y: 2, width: 0.8, height: 0.5), CGRect(x: 9.3, y: 2, width: 0.8, height: 0.5),
            ]), NSColor.white.withAlphaComponent(0.85), unit: u))

        default:
            let eyeLayer = CAShapeLayer()
            eyeLayer.bounds = CGRect(x: 0, y: 0, width: 16 * u, height: 10 * u)
            eyeLayer.anchorPoint = CGPoint(x: 0.5, y: 0.3)
            eyeLayer.position = CGPoint(x: 8 * u, y: 3 * u)
            eyeLayer.fillColor = NSColor.black.cgColor
            content.addSublayer(eyeLayer)
            eyes = eyeLayer
        }
        return CGSize(width: 16 * u, height: (10 + top) * u)
    }

    /// An orange apple with a bite, a leaf and Clawd's eyes.
    private func buildApple() -> CGSize {
        let u: CGFloat = 1.3
        let body: [CGRect] = [
            CGRect(x: 2, y: 3, width: 3, height: 1), CGRect(x: 7, y: 3, width: 3, height: 1),
            CGRect(x: 1, y: 4, width: 11, height: 1),
            CGRect(x: 0, y: 5, width: 12, height: 1),
            CGRect(x: 0, y: 6, width: 10, height: 1),
            CGRect(x: 0, y: 7, width: 9, height: 2),
            CGRect(x: 0, y: 9, width: 10, height: 1),
            CGRect(x: 0, y: 10, width: 12, height: 1),
            CGRect(x: 1, y: 11, width: 10, height: 1),
            CGRect(x: 2, y: 12, width: 3, height: 1), CGRect(x: 7, y: 12, width: 3, height: 1),
        ]
        let leaf: [CGRect] = [CGRect(x: 7, y: 0, width: 2, height: 1), CGRect(x: 6, y: 1, width: 2, height: 1), CGRect(x: 6, y: 2, width: 1, height: 1)]
        content.addSublayer(pixels(body, SpriteColors.clay, unit: u))
        content.addSublayer(pixels(leaf, SpriteColors.clayDeep, unit: u))
        let eyeLayer = pixels([CGRect(x: 3, y: 6, width: 1, height: 2), CGRect(x: 7, y: 6, width: 1, height: 2)], .black, unit: u)
        content.addSublayer(eyeLayer)
        eyes = eyeLayer
        return CGSize(width: 12 * u, height: 13 * u)
    }

    private func buildFolder() -> CGSize {
        let u: CGFloat = 2.5
        content.addSublayer(pixels([CGRect(x: 1, y: 0, width: 5, height: 1.5)], SpriteColors.folderBack, unit: u))
        content.addSublayer(pixels([CGRect(x: 0, y: 1, width: 14, height: 9)], SpriteColors.folderBack, unit: u))
        content.addSublayer(pixels([CGRect(x: 0, y: 3, width: 14, height: 7)], SpriteColors.folder, unit: u))
        content.addSublayer(pixels([CGRect(x: 3, y: 10, width: 1, height: 1.5), CGRect(x: 10, y: 10, width: 1, height: 1.5)], SpriteColors.clay, unit: u))
        let eyeLayer = pixels([CGRect(x: 4, y: 5, width: 1, height: 2), CGRect(x: 9, y: 5, width: 1, height: 2)], .black, unit: u)
        content.addSublayer(eyeLayer)
        eyes = eyeLayer
        return CGSize(width: 14 * u, height: 11.5 * u)
    }

    /// A fourth window button in Clawd orange.
    private func buildTrafficLight() -> CGSize {
        let side: CGFloat = 12
        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: 0.5, y: 0.5, width: side - 1, height: side - 1), transform: nil)
        dot.fillColor = SpriteColors.clay.cgColor
        dot.strokeColor = SpriteColors.clayDeep.cgColor
        dot.lineWidth = 0.6
        dot.frame = CGRect(x: 0, y: 0, width: side, height: side)
        content.addSublayer(dot)

        let eyeLayer = CAShapeLayer()
        let eyePath = CGMutablePath()
        eyePath.addRect(CGRect(x: 3.6, y: 3.4, width: 1.3, height: 2.8))
        eyePath.addRect(CGRect(x: 7.1, y: 3.4, width: 1.3, height: 2.8))
        eyeLayer.path = eyePath
        eyeLayer.fillColor = NSColor.black.cgColor
        eyeLayer.frame = CGRect(x: 0, y: 0, width: side, height: side)
        content.addSublayer(eyeLayer)
        eyes = eyeLayer
        return CGSize(width: side, height: side)
    }

    // MARK: Poses

    private func applyPose() {
        let u: CGFloat = 2.5
        for part in [content, leftArm, rightArm, legsA, legsB, eyes].compactMap({ $0 }) {
            part.removeAllAnimations()
            part.transform = CATransform3DIdentity
        }
        extras.sublayers?.forEach { $0.removeFromSuperlayer() }
        legsA?.isHidden = false
        legsB?.isHidden = false
        setEyes(.open)

        switch pose {
        case .stand:
            blink(eyes)
        case .walk:
            loop(legsA, keyframes("transform.translation.y", [0, -0.9 * u, 0], times: [0, 0.5, 1], duration: 0.34))
            loop(legsB, keyframes("transform.translation.y", [0, -0.9 * u, 0], times: [0, 0.5, 1], duration: 0.34, offset: 0.17))
            loop(content, keyframes("transform.translation.y", [0, -0.45 * u, 0], times: [0, 0.5, 1], duration: 0.17))
            blink(eyes)
        case .fall:
            leftArm?.transform = CATransform3DMakeTranslation(0, -2.4 * u, 0)
            rightArm?.transform = CATransform3DMakeTranslation(0, -2.4 * u, 0)
            legsA?.transform = CATransform3DMakeTranslation(-0.4 * u, 0, 0)
            legsB?.transform = CATransform3DMakeTranslation(0.4 * u, 0, 0)
            eyes?.transform = CATransform3DMakeScale(1, 1.25, 1)
        case .sit:
            legsA?.isHidden = true
            legsB?.isHidden = true
            content.transform = CATransform3DMakeTranslation(0, 2 * u, 0)
            blink(eyes)
        case .sleep:
            legsA?.isHidden = true
            legsB?.isHidden = true
            content.transform = CATransform3DMakeTranslation(0, 2 * u, 0)
            setEyes(.closed)
            loop(content, keyframes("transform.translation.y", [2 * u, 1.6 * u, 2 * u], times: [0, 0.5, 1], duration: 2.4))
            addSnoring()
        case .happy:
            setEyes(.happy)
            loop(content, keyframes("transform.translation.y", [0, -3 * u, 0, 0], times: [0, 0.3, 0.6, 1], duration: 0.5, curves: [.easeOut, .easeIn, .linear]))
            addHeart()
        case .work:
            loop(leftArm, keyframes("transform.translation.y", [0, -0.9 * u, 0], times: [0, 0.5, 1], duration: 0.28))
            loop(rightArm, keyframes("transform.translation.y", [0, -0.9 * u, 0], times: [0, 0.5, 1], duration: 0.28, offset: 0.14))
            blink(eyes)
        case .dance:
            // Paws up, one side and then the other, with a little sway.
            loop(leftArm, keyframes("transform.translation.y", [0, -3.2 * u, -3.2 * u, 0], times: [0, 0.2, 0.45, 0.65], duration: 1.2, curves: [.easeOut, .linear, .easeIn]))
            loop(rightArm, keyframes("transform.translation.y", [0, -3.2 * u, -3.2 * u, 0], times: [0, 0.2, 0.45, 0.65], duration: 1.2, offset: 0.6, curves: [.easeOut, .linear, .easeIn]))
            loop(content, keyframes("transform.rotation.z", [-0.07, 0.07, -0.07], times: [0, 0.5, 1], duration: 1.2, curves: [.easeInEaseOut, .easeInEaseOut]))
            loop(legsA, keyframes("transform.translation.y", [0, -0.8 * u, 0], times: [0, 0.5, 1], duration: 0.6))
            loop(legsB, keyframes("transform.translation.y", [0, -0.8 * u, 0], times: [0, 0.5, 1], duration: 0.6, offset: 0.3))
            blink(eyes)
        }
    }

    private enum EyeStyle {
        case open, closed, happy
    }

    private func setEyes(_ style: EyeStyle) {
        guard look == .clawd, let eyes else { return }
        let u: CGFloat = 2.5
        let rects: [CGRect]
        switch style {
        case .open:
            rects = [CGRect(x: 4, y: 2, width: 1, height: 2), CGRect(x: 11, y: 2, width: 1, height: 2)]
        case .closed:
            rects = [CGRect(x: 3.5, y: 3, width: 2, height: 0.5), CGRect(x: 10.5, y: 3, width: 2, height: 0.5)]
        case .happy:
            rects = [4, 11].flatMap { (column: CGFloat) in [
                CGRect(x: column - 0.5, y: 2.75, width: 0.5, height: 1),
                CGRect(x: column, y: 2.25, width: 1, height: 0.5),
                CGRect(x: column + 1, y: 2.75, width: 0.5, height: 1),
            ] }
        }
        let path = CGMutablePath()
        for rect in rects {
            path.addRect(CGRect(x: rect.minX * u, y: (rect.minY + bodyTop) * u, width: rect.width * u, height: rect.height * u))
        }
        eyes.path = path
    }

    private func addHeart() {
        let u: CGFloat = 1.6
        let heart = pixels([
            CGRect(x: 1, y: 0, width: 2, height: 1), CGRect(x: 4, y: 0, width: 2, height: 1),
            CGRect(x: 0, y: 1, width: 7, height: 2), CGRect(x: 1, y: 3, width: 5, height: 1),
            CGRect(x: 2, y: 4, width: 3, height: 1), CGRect(x: 3, y: 5, width: 1, height: 1),
        ], SpriteColors.heart, unit: u)
        heart.position = CGPoint(x: size.width + 2, y: -6)
        extras.addSublayer(heart)
        loop(heart, keyframes("transform.translation.y", [0, -4, 0], times: [0, 0.5, 1], duration: 1))
    }

    private func addSnoring() {
        for index in 0..<3 {
            let scale = 0.9 + CGFloat(index) * 0.35
            let z = pixels([
                CGRect(x: 0, y: 0, width: 5, height: 1), CGRect(x: 3, y: 1, width: 1, height: 1),
                CGRect(x: 2, y: 2, width: 1, height: 1), CGRect(x: 1, y: 3, width: 1, height: 1),
                CGRect(x: 0, y: 4, width: 5, height: 1),
            ], .white, unit: scale)
            z.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
            z.lineWidth = 0.5
            z.position = CGPoint(x: size.width * 0.85, y: 0)
            z.opacity = 0
            extras.addSublayer(z)
            let offset = Double(2 - index) * 1
            loop(z, keyframes("transform.translation", [NSValue(size: .zero), NSValue(size: CGSize(width: 14, height: -18))], times: [0, 1], duration: 3, offset: offset))
            loop(z, keyframes("opacity", [0, 1, 1, 0], times: [0, 0.2, 0.7, 1], duration: 3, offset: offset))
        }
    }

    private func puff() {
        guard let parent = layer.superlayer else { return }
        let center = CGPoint(x: layer.position.x, y: layer.position.y - size.height / 2)
        for index in 0..<7 {
            let angle = Double(index) / 7 * 2 * .pi
            let dot = CAShapeLayer()
            let radius = CGFloat.random(in: 3...5)
            dot.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
            dot.fillColor = NSColor(white: 0.96, alpha: 0.95).cgColor
            dot.strokeColor = NSColor.black.withAlphaComponent(0.25).cgColor
            dot.lineWidth = 0.6
            dot.position = center
            dot.opacity = 0
            parent.addSublayer(dot)

            let distance: CGFloat = 16
            let move = CABasicAnimation(keyPath: "transform.translation")
            move.toValue = NSValue(size: CGSize(width: cos(angle) * distance, height: sin(angle) * distance))
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.4
            grow.toValue = 1.2
            let fade = keyframes("opacity", [0, 1, 0], times: [0, 0.2, 1], duration: 0.45)
            fade.repeatCount = 1
            let group = CAAnimationGroup()
            group.animations = [move, grow, fade]
            group.duration = 0.45
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            dot.add(group, forKey: "puff")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dot.removeFromSuperlayer() }
        }
    }

    // MARK: Helpers

    private func blink(_ layer: CALayer?) {
        guard let layer else { return }
        loop(layer, keyframes("transform.scale.y", [1, 1, 0.1, 1, 1, 0.1, 1, 1], times: [0, 0.84, 0.865, 0.89, 0.92, 0.945, 0.97, 1], duration: 5.2))
    }

    private func pixels(_ rects: [CGRect], _ color: NSColor, unit: CGFloat) -> CAShapeLayer {
        let shape = CAShapeLayer()
        let path = CGMutablePath()
        var box = CGRect.null
        for rect in rects {
            let frame = CGRect(x: rect.minX * unit, y: rect.minY * unit, width: rect.width * unit, height: rect.height * unit)
            path.addRect(frame)
            box = box.union(frame)
        }
        shape.path = path
        shape.fillColor = color.cgColor
        shape.frame = CGRect(x: 0, y: 0, width: max(box.maxX, 1), height: max(box.maxY, 1))
        return shape
    }

    private func loop(_ layer: CALayer?, _ animation: CAAnimation) {
        guard !reduceMotion, let layer else { return }
        layer.add(animation, forKey: (animation as? CAPropertyAnimation)?.keyPath)
    }

    private func keyframes(
        _ keyPath: String,
        _ values: [Any],
        times: [Double],
        duration: Double,
        offset: Double = 0,
        curves: [CAMediaTimingFunctionName]? = nil
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timeOffset = offset
        if let curves {
            animation.timingFunctions = curves.map { CAMediaTimingFunction(name: $0) }
        }
        return animation
    }
}

private enum SpriteColors {
    static let clay = NSColor(srgbRed: 215 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
    static let clayLight = NSColor(srgbRed: 236 / 255, green: 150 / 255, blue: 118 / 255, alpha: 1)
    static let clayDeep = NSColor(srgbRed: 176 / 255, green: 86 / 255, blue: 58 / 255, alpha: 1)
    static let folder = NSColor(srgbRed: 0.38, green: 0.7, blue: 0.96, alpha: 1)
    static let folderBack = NSColor(srgbRed: 0.28, green: 0.58, blue: 0.88, alpha: 1)
    static let spark = NSColor(srgbRed: 1, green: 0.84, blue: 0.3, alpha: 1)
    static let heart = NSColor(srgbRed: 1, green: 0.43, blue: 0.5, alpha: 1)
    static let suitRed = NSColor(srgbRed: 0.84, green: 0.16, blue: 0.17, alpha: 1)
    static let suitBlue = NSColor(srgbRed: 0.17, green: 0.33, blue: 0.8, alpha: 1)
    static let suitLine = NSColor(srgbRed: 0.45, green: 0.05, blue: 0.07, alpha: 0.9)
    static let hair = NSColor(srgbRed: 0.97, green: 0.93, blue: 0.78, alpha: 1)
    static let hairShade = NSColor(srgbRed: 0.9, green: 0.83, blue: 0.6, alpha: 1)
}
