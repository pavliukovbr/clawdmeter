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

    var body: some View {
        ZStack(alignment: .topLeading) {
            PixelShape(Sprite.legs).fill(color)
            breathing(upperBody)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) {
            accessories
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(x: accessoriesOnLeft ? -1 : 1, y: 1)
        }
    }

    // MARK: Body

    private var upperBody: some View {
        let eyes = Sprite.eyes(for: mood)
        return ZStack(alignment: .topLeading) {
            PixelShape(eyes).fill(eyeColor)
            PixelShape(Sprite.body, cutouts: eyes).fill(color)
            if moving, let lids = Sprite.blinkingEyes(for: mood) {
                ForEach(lids.indices, id: \.self) { index in
                    eyelids(over: lids[index], lags: mood == .idle ? [0, 0.3] : [0])
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func breathing(_ content: some View) -> some View {
        if moving {
            content.bob(height: bobHeight * unit, period: bobPeriod, in: size)
        } else {
            content
        }
    }

    private var bobHeight: CGFloat {
        switch mood {
        case .idle: 0.6
        case .busy: 0.6
        case .tired: 0.35
        case .sleeping: 0.4
        case .happy: 1
        }
    }

    /// Every period divides six seconds, so all the motion lines up into one loop.
    private var bobPeriod: TimeInterval {
        switch mood {
        case .idle: 3
        case .busy: 1.5
        case .tired: 3
        case .sleeping: 6
        case .happy: 0.75
        }
    }

    // MARK: Eyes

    /// A lid in body color swings past the eye on a wide circle, which reads as a quick
    /// blink. Each lag adds another lid trailing by that many radians.
    private func eyelids(over eye: CGRect, lags: [Double]) -> some View {
        let width = eye.width * unit
        let height = eye.height * unit
        let radius = 38 * unit

        return ZStack {
            ForEach(lags, id: \.self) { lag in
                Rectangle()
                    .fill(color)
                    .frame(width: width * 1.6, height: height + 0.6 * unit)
                    .rotationEffect(.radians(-lag))
                    .offset(x: radius + radius * cos(lag), y: -radius * sin(lag))
                    .frame(width: width, height: height)
                    .spin(period: 6, anchor: UnitPoint(x: 0.5 + radius / width, y: 0.5))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .offset(x: eye.minX * unit, y: eye.minY * unit)
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
            PixelShape(Sprite.heart, columns: 7)
                .fill(Palette.heart)
                .frame(width: 7 * unit * 0.55, height: 6 * unit * 0.55)
                .offset(x: 15.5 * unit, y: -2.2 * unit)
                .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
        case .idle:
            EmptyView()
        }
    }

    /// Three z's that light up one after another as a soft wedge sweeps over them.
    private var snoring: some View {
        let letters: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [(15.5, 1.3, 0.34), (17.6, -0.4, 0.44), (20.2, -2.4, 0.54)]
        let center = CGPoint(x: 24 * unit, y: 2.8 * unit)
        let reach = 10 * unit

        return ZStack(alignment: .topLeading) {
            ForEach(letters.indices, id: \.self) { index in
                let letter = letters[index]
                PixelShape(Sprite.z, columns: 5)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 5 * unit * letter.scale, height: 5 * unit * letter.scale)
                    .scaleEffect(x: accessoriesOnLeft ? -1 : 1, y: 1)
                    .offset(x: letter.x * unit, y: letter.y * unit)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .mask(alignment: .topLeading) {
            if moving {
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
                .offset(x: center.x - reach, y: center.y - reach)
            } else {
                Rectangle()
            }
        }
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

// MARK: Shapes

enum Sprite {
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

    static func blinkingEyes(for mood: ClawdMood) -> [CGRect]? {
        switch mood {
        case .idle, .busy, .tired: eyes(for: mood)
        case .sleeping, .happy: nil
        }
    }

    static let body = [
        CGRect(x: 2, y: 0, width: 12, height: 4),
        CGRect(x: 0, y: 4, width: 16, height: 2),
        CGRect(x: 2, y: 6, width: 12, height: 2),
    ]

    /// Legs start one row inside the body so they stay attached while it breathes.
    static let legs = [3, 5, 10, 12].map { CGRect(x: CGFloat($0), y: 7, width: 1, height: 3) }

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
