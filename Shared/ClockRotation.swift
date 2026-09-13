import SwiftUI
import WidgetKit

/// Rotation driven by the widget host clock, so it keeps moving between timeline entries.
/// WidgetKit ships this effect for clock hands but keeps it out of the public interface,
/// so the type is looked up at runtime and built from its Codable form.
/// If it ever goes away the views simply stay still.
enum ClockRotation {
    private static let effectType: (any (ViewModifier & Decodable).Type)? = {
        _typeByName("9WidgetKit24_ClockHandRotationEffectV") as? any (ViewModifier & Decodable).Type
    }()

    static var isAvailable: Bool { effectType != nil }

    static func effect(period: TimeInterval, anchor: UnitPoint) -> (any ViewModifier)? {
        guard let effectType else { return nil }
        let json = "{\"period\":\(period),\"anchor\":[\(anchor.x),\(anchor.y)],\"timeZone\":{\"identifier\":\"GMT\"}}"
        return try? JSONDecoder().decode(effectType, from: Data(json.utf8))
    }
}

private struct MotionClockKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// When set, motion is computed from this date instead of the widget host clock.
    /// The app drives it from a TimelineView so the pet moves the same way there.
    var motionClock: Date? {
        get { self[MotionClockKey.self] }
        set { self[MotionClockKey.self] = newValue }
    }
}

extension View {
    /// Spins the view once per `period` seconds. Periods should divide a day evenly
    /// so every spin stays in phase with the others.
    func spin(period: TimeInterval, anchor: UnitPoint = .center, clockwise: Bool = true) -> some View {
        modifier(SpinModifier(period: period, anchor: anchor, clockwise: clockwise))
    }

    /// Moves the view around a circle without turning it. `offset` points from the
    /// start position to the center of the circle, `phase` starts further along it.
    func orbit(period: TimeInterval, offset: CGSize, phase: Double = 0, in size: CGSize, clockwise: Bool = true) -> some View {
        let turn = clockwise ? phase : -phase
        let rotated = CGSize(
            width: offset.width * cos(turn) - offset.height * sin(turn),
            height: offset.width * sin(turn) + offset.height * cos(turn)
        )
        let center = UnitPoint(x: 0.5 + rotated.width / size.width, y: 0.5 + rotated.height / size.height)
        return spin(period: period, anchor: .center, clockwise: !clockwise)
            .spin(period: period, anchor: center, clockwise: clockwise)
            .offset(x: offset.width - rotated.width, y: offset.height - rotated.height)
    }

    /// Eases the view out along `vector` and back once per period without turning it.
    /// Two opposite orbits cancel sideways and add up along the vector. `phase` delays the
    /// motion in radians, and `centered` swings to both sides of the resting spot.
    func oscillate(_ vector: CGVector, period: TimeInterval, phase: Double = 0, centered: Bool = false, in size: CGSize) -> some View {
        let quarter = hypot(vector.dx, vector.dy) / 4
        let angle = atan2(vector.dy, vector.dx)
        let forward = CGSize(width: quarter * cos(angle - phase), height: quarter * sin(angle - phase))
        let backward = CGSize(width: quarter * cos(angle + phase), height: quarter * sin(angle + phase))
        let rest = (1 - cos(phase)) / 2 - (centered ? 0.5 : 0)
        return orbit(period: period, offset: forward, in: size, clockwise: true)
            .orbit(period: period, offset: backward, in: size, clockwise: false)
            .offset(x: vector.dx * rest, y: vector.dy * rest)
    }

    /// Eases the view up by `height` and back down once per period.
    func bob(height: CGFloat, period: TimeInterval, phase: Double = 0, in size: CGSize) -> some View {
        oscillate(CGVector(dx: 0, dy: -height), period: period, phase: phase, in: size)
    }
}

private struct SpinModifier: ViewModifier {
    let period: TimeInterval
    let anchor: UnitPoint
    let clockwise: Bool

    @Environment(\.motionClock) private var clock

    func body(content: Content) -> some View {
        if let clock {
            let phase = clock.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
            content.rotationEffect(.degrees(phase * (clockwise ? 360 : -360)), anchor: anchor)
        } else if clockwise {
            content.applyingClockRotation(period: period, anchor: anchor)
        } else {
            // Mirror, spin, mirror back: the same spin running the other way.
            content
                .scaleEffect(x: -1, y: 1)
                .applyingClockRotation(period: period, anchor: UnitPoint(x: 1 - anchor.x, y: anchor.y))
                .scaleEffect(x: -1, y: 1)
        }
    }
}

private extension View {
    @ViewBuilder
    func applyingClockRotation(period: TimeInterval, anchor: UnitPoint) -> some View {
        if let effect = ClockRotation.effect(period: period, anchor: anchor) {
            applying(effect)
        } else {
            self
        }
    }

    func applying(_ modifier: any ViewModifier) -> AnyView {
        func apply<M: ViewModifier>(_ modifier: M) -> AnyView { AnyView(self.modifier(modifier)) }
        return apply(modifier)
    }
}
