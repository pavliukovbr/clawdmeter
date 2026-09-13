import SwiftUI

enum ClawdMood: String, Codable, CaseIterable {
    case idle, busy, tired, sleeping, happy
}

/// Clawd drawn on a 16 by 10 pixel grid. Every animation is built from spins so it
/// can run inside a widget, where views are rendered ahead of time.
struct ClawdView: View {
    var mood: ClawdMood = .idle
    var unit: CGFloat = 3
    var color: Color = Palette.clay
    var eyeColor: Color = .black
    var animated = true
    /// Puts the z's, drop and heart on the left, for when Clawd stands at the right edge.
    var accessoriesOnLeft = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let columns: CGFloat = 16
    static let rows: CGFloat = 10

    private var size: CGSize { CGSize(width: Self.columns * unit, height: Self.rows * unit) }
    private var moving: Bool { animated && !reduceMotion }
    private var motion: Motion { Motion(mood: mood) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            legs
            arm(Sprite.leftArm, phase: motion.leftArmPhase)
            arm(Sprite.rightArm, phase: motion.rightArmPhase)
            core
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            accessories
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(x: accessoriesOnLeft ? -1 : 1, y: 1)
        }
    }

    // MARK: Body

    @ViewBuilder
    private var legs: some View {
        if moving && motion.feetLift > 0 {
            let lift = CGVector(dx: 0, dy: -motion.feetLift * unit)
            pixels(Sprite.legs(at: [0, 2]))
                .oscillate(lift, period: 1, in: size)
            pixels(Sprite.legs(at: [1, 3]))
                .oscillate(lift, period: 1, phase: .pi, in: size)
        } else {
            pixels(Sprite.legs)
        }
    }

    @ViewBuilder
    private func arm(_ rect: CGRect, phase: Double) -> some View {
        if moving {
            pixels([rect])
                .oscillate(CGVector(dx: 0, dy: -motion.armLift * unit), period: motion.armPeriod, phase: phase, in: size)
        } else {
            pixels([rect])
        }
    }

    @ViewBuilder
    private var core: some View {
        let eyes = Sprite.eyes(for: mood)
        if moving {
            ZStack(alignment: .topLeading) {
                pixels([Sprite.core])
                animatedEyes(eyes)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .oscillate(CGVector(dx: 0, dy: -motion.bodyLift * unit), period: motion.bodyPeriod, in: size)
        } else {
            // Eyes are cut out of the body so they still read when the widget is tinted.
            ZStack(alignment: .topLeading) {
                PixelShape(eyes).fill(eyeColor)
                PixelShape([Sprite.core], cutouts: eyes).fill(color)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    private func pixels(_ rects: [CGRect]) -> some View {
        PixelShape(rects)
            .fill(color)
            .frame(width: size.width, height: size.height)
    }

    // MARK: Eyes

    private func animatedEyes(_ eyes: [CGRect]) -> some View {
        ZStack(alignment: .topLeading) {
            glancing(PixelShape(eyes).fill(eyeColor).frame(width: size.width, height: size.height))
            if motion.blinks {
                ForEach(Array(Sprite.sockets(for: eyes, reach: motion.glance).enumerated()), id: \.offset) { _, socket in
                    eyelids(over: socket, lags: motion.doubleBlink ? [0, 0.3] : [0])
                }
            }
        }
    }

    /// Two harmonics give a look to one side, a short hold, and a look to the other side.
    @ViewBuilder
    private func glancing(_ eyes: some View) -> some View {
        if motion.glance > 0 {
            let reach = motion.glance * unit * 9 / 8
            eyes
                .oscillate(CGVector(dx: -2 * reach, dy: 0), period: 12, centered: true, in: size)
                .oscillate(CGVector(dx: 2 * reach / 9, dy: 0), period: 4, centered: true, in: size)
        } else {
            eyes
        }
    }

    /// A lid in body color swings past the eye on a wide circle, which reads as a quick
    /// blink. Each lag adds another lid trailing by that many radians.
    private func eyelids(over socket: CGRect, lags: [Double]) -> some View {
        let width = socket.width * unit
        let height = socket.height * unit
        let radius = 38 * unit

        return ZStack {
            ForEach(lags, id: \.self) { lag in
                Rectangle()
                    .fill(color)
                    .frame(width: width * 1.3, height: height + 0.6 * unit)
                    .rotationEffect(.radians(-lag))
                    .offset(x: radius + radius * cos(lag), y: -radius * sin(lag))
                    .frame(width: width, height: height)
                    .spin(period: 6, anchor: UnitPoint(x: 0.5 + radius / width, y: 0.5))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .offset(x: socket.minX * unit, y: socket.minY * unit)
    }

    // MARK: Accessories

    @ViewBuilder
    private var accessories: some View {
        switch mood {
        case .sleeping:
            snoring
        case .busy, .tired:
            sweatDrop(period: mood == .busy ? 2 : 3)
        case .happy:
            heart
        case .idle:
            EmptyView()
        }
    }

    private var heart: some View {
        let area = CGSize(width: 7 * unit * 0.55, height: 6 * unit * 0.55)
        return PixelShape(Sprite.heart, columns: 7)
            .fill(Palette.heart)
            .frame(width: area.width, height: area.height)
            .modifier(Floating(enabled: moving, lift: 0.7 * unit, area: area))
            .offset(x: 15.5 * unit, y: -2.2 * unit)
            .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
    }

    /// Three z's that light up one after another while the group floats up a little.
    @ViewBuilder
    private var snoring: some View {
        let letters: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [(15.5, 2.6, 0.32), (17.4, 1.2, 0.42), (19.6, -0.6, 0.52)]
        let group = ZStack(alignment: .topLeading) {
            ForEach(letters.indices, id: \.self) { index in
                let letter = letters[index]
                zGlyph(side: 5 * unit * letter.scale)
                    .offset(x: letter.x * unit, y: letter.y * unit)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)

        if moving {
            let reach = 10 * unit
            group
                .oscillate(CGVector(dx: 0.4 * unit, dy: -0.8 * unit), period: 3, in: size)
                .mask(alignment: .topLeading) {
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.08),
                            .init(color: .white, location: 0.2),
                            .init(color: .clear, location: 0.3),
                            .init(color: .clear, location: 1),
                        ],
                        center: .center
                    )
                    .frame(width: reach * 2, height: reach * 2)
                    .spin(period: 3)
                    .offset(x: 24 * unit - reach, y: 3.6 * unit - reach)
                }
        } else {
            group
        }
    }

    private func zGlyph(side: CGFloat) -> some View {
        PixelShape(Sprite.z, columns: 5)
            .fill(Color.white.opacity(0.85))
            .frame(width: side, height: side)
            .scaleEffect(x: accessoriesOnLeft ? -1 : 1, y: 1)
    }

    /// A drop that slides off the side of the head and fades.
    @ViewBuilder
    private func sweatDrop(period: TimeInterval) -> some View {
        let start = CGPoint(x: 14.4 * unit, y: -0.4 * unit)
        let area = CGSize(width: 1.6 * unit, height: 2.2 * unit)
        let drop = DropShape()
            .fill(Palette.sweat)
            .frame(width: area.width, height: area.height)

        if moving {
            let radius = 3 * unit
            drop
                .orbit(period: period, offset: CGSize(width: -radius, height: 0), in: area)
                .offset(x: start.x, y: start.y)
                .mask(alignment: .topLeading) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.25),
                            .init(color: .white, location: 0.55),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 3.2 * unit, height: 5.4 * unit)
                    .offset(x: start.x - 0.6 * unit, y: start.y - 0.8 * unit)
                }
        } else {
            drop.offset(x: start.x, y: start.y + 0.6 * unit)
        }
    }
}

/// How each mood moves. Every period divides twelve seconds, so the loops line up.
private struct Motion {
    var bodyLift: CGFloat = 0.6
    var bodyPeriod: TimeInterval = 3
    var armLift: CGFloat = 0.6
    var armPeriod: TimeInterval = 3
    var leftArmPhase = 0.7
    var rightArmPhase = 0.7
    var feetLift: CGFloat = 0
    var glance: CGFloat = 0
    var blinks = true
    var doubleBlink = false

    init(mood: ClawdMood) {
        switch mood {
        case .idle:
            glance = 0.4
            doubleBlink = true
        case .busy:
            bodyLift = 0.45
            bodyPeriod = 1.5
            armLift = 0.7
            armPeriod = 0.5
            leftArmPhase = 0
            rightArmPhase = .pi
            feetLift = 0.35
        case .tired:
            bodyLift = 0.3
            armLift = 0.35
            leftArmPhase = 1
            rightArmPhase = 1
        case .sleeping:
            bodyLift = 0.35
            bodyPeriod = 6
            armLift = 0.3
            armPeriod = 6
            leftArmPhase = 0.6
            rightArmPhase = 0.6
            blinks = false
        case .happy:
            bodyLift = 1
            bodyPeriod = 0.75
            armLift = 1.1
            armPeriod = 0.75
            leftArmPhase = 0.9
            rightArmPhase = 0.9
            blinks = false
        }
    }
}

private struct Floating: ViewModifier {
    var enabled: Bool
    var lift: CGFloat
    var area: CGSize

    func body(content: Content) -> some View {
        if enabled {
            content.oscillate(CGVector(dx: 0, dy: -lift), period: 1.5, in: area)
        } else {
            content
        }
    }
}

// MARK: Shapes

enum Sprite {
    static let core = CGRect(x: 2, y: 0, width: 12, height: 8)
    static let leftArm = CGRect(x: 0, y: 4, width: 2, height: 2)
    static let rightArm = CGRect(x: 14, y: 4, width: 2, height: 2)
    static let body = [core, leftArm, rightArm]

    /// Legs start one row inside the body so they stay attached while it breathes.
    static let legColumns: [CGFloat] = [3, 5, 10, 12]
    static let legs = legs(at: [0, 1, 2, 3])

    static func legs(at indices: [Int]) -> [CGRect] {
        indices.map { CGRect(x: legColumns[$0], y: 7, width: 1, height: 3) }
    }

    static func eyes(for mood: ClawdMood) -> [CGRect] {
        [4, 11].flatMap { (column: CGFloat) -> [CGRect] in
            switch mood {
            case .idle, .busy:
                [CGRect(x: column, y: 2, width: 1, height: 2)]
            case .tired:
                [CGRect(x: column, y: 3, width: 1, height: 1)]
            case .sleeping:
                [CGRect(x: column - 0.5, y: 3, width: 2, height: 0.5)]
            case .happy:
                [
                    CGRect(x: column - 0.5, y: 2.75, width: 0.5, height: 1),
                    CGRect(x: column, y: 2.25, width: 1, height: 0.5),
                    CGRect(x: column + 1, y: 2.75, width: 0.5, height: 1),
                ]
            }
        }
    }

    /// The area an eye can wander around in, which is also where its lid sweeps.
    static func sockets(for eyes: [CGRect], reach: CGFloat) -> [CGRect] {
        eyes.map { $0.insetBy(dx: -(reach + 0.1), dy: 0) }
    }

    static let heart = [
        CGRect(x: 1, y: 0, width: 2, height: 1), CGRect(x: 4, y: 0, width: 2, height: 1),
        CGRect(x: 0, y: 1, width: 7, height: 2),
        CGRect(x: 1, y: 3, width: 5, height: 1),
        CGRect(x: 2, y: 4, width: 3, height: 1),
        CGRect(x: 3, y: 5, width: 1, height: 1),
    ]

    static let z = [
        CGRect(x: 0, y: 0, width: 5, height: 1),
        CGRect(x: 3, y: 1, width: 1, height: 1),
        CGRect(x: 2, y: 2, width: 1, height: 1),
        CGRect(x: 1, y: 3, width: 1, height: 1),
        CGRect(x: 0, y: 4, width: 5, height: 1),
    ]
}

struct PixelShape: Shape {
    var rects: [CGRect]
    var cutouts: [CGRect]
    var columns: CGFloat

    init(_ rects: [CGRect], cutouts: [CGRect] = [], columns: CGFloat = ClawdView.columns) {
        self.rects = rects
        self.cutouts = cutouts
        self.columns = columns
    }

    func path(in rect: CGRect) -> Path {
        let unit = rect.width / columns
        let solid = Self.path(rects, unit: unit, origin: rect.origin)
        guard !cutouts.isEmpty else { return solid }
        return solid.subtracting(Self.path(cutouts, unit: unit, origin: rect.origin))
    }

    private static func path(_ rects: [CGRect], unit: CGFloat, origin: CGPoint) -> Path {
        var path = Path()
        for pixel in rects {
            path.addRect(CGRect(
                x: origin.x + pixel.minX * unit,
                y: origin.y + pixel.minY * unit,
                width: pixel.width * unit,
                height: pixel.height * unit
            ))
        }
        return path
    }
}

struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
            control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.35)
        )
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.35)
        )
        return path
    }
}
