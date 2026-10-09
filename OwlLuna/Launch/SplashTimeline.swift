import SwiftUI

/// Where the splash is, in milliseconds: `time` runs from its first frame, `leaving` from the hand-over and is nil until then.
struct SplashClock: Equatable, Sendable {
    var time: Double
    var leaving: Double?

    /// The time on the leaving clock, far in the past while the splash is still holding.
    var exit: Double { leaving ?? -.greatestFiniteMagnitude }
}

/// How a value travels between its two ends.
enum SplashCurve: Sendable {
    case linear
    /// A cubic by its two control points: x, y, x, y.
    case bezier(Double, Double, Double, Double)
    /// Passes its end and swings back onto it; by the end the swing is down to e to the minus `settle` of itself.
    case spring(damping: Double, settle: Double)

    static let glide = SplashCurve.bezier(0.16, 1, 0.3, 1)
    static let bounce = SplashCurve.bezier(0.34, 1.56, 0.64, 1)
    static let easeIn = SplashCurve.bezier(0.42, 0, 1, 1)
    static let easeOut = SplashCurve.bezier(0, 0, 0.58, 1)
    static let easeInOut = SplashCurve.bezier(0.42, 0, 0.58, 1)

    func value(_ fraction: Double) -> Double {
        let t = min(max(fraction, 0), 1)
        switch self {
        case .linear:
            return t
        case let .bezier(x1, y1, x2, y2):
            return UnitCurve.bezier(startControlPoint: UnitPoint(x: x1, y: y1), endControlPoint: UnitPoint(x: x2, y: y2)).value(at: t)
        case let .spring(damping, settle):
            guard t < 1 else { return 1 }
            let damped = settle / damping * (1 - damping * damping).squareRoot()
            return 1 - exp(-settle * t) * (cos(damped * t) + settle / damped * sin(damped * t))
        }
    }
}

/// One move on the splash clock.
struct SplashBeat: Sendable {
    var delay: Double
    var duration: Double
    var curve: SplashCurve = .glide

    /// 0 until the beat starts and 1 once it is over; between, its curve.
    func progress(_ time: Double) -> Double {
        guard duration > 0 else { return time >= delay ? 1 : 0 }
        return curve.value((time - delay) / duration)
    }

    /// The beat played again and again; alternating, every other turn runs backwards.
    func cycle(_ time: Double, alternating: Bool = false) -> Double {
        let turns = max(0, time - delay) / duration
        let whole = turns.rounded(.down)
        let backwards = alternating && Int(whole) % 2 == 1
        return curve.value(backwards ? 1 - (turns - whole) : turns - whole)
    }
}

/// A value that passes through several stops, each stop naming the curve that leads on from it.
struct SplashTrack: Sendable {
    struct Stop: Sendable {
        var at: Double
        var value: Double
        var curve: SplashCurve = .linear
    }

    var delay: Double
    var duration: Double
    var stops: [Stop]

    func value(_ time: Double, repeating: Bool = false) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        var fraction = (time - delay) / duration
        if repeating, fraction > 0 { fraction -= fraction.rounded(.down) }
        if fraction <= first.at { return first.value }
        for (from, to) in zip(stops, stops.dropFirst()) where fraction < to.at {
            return mix(from.value, to.value, from.curve.value((fraction - from.at) / (to.at - from.at)))
        }
        return last.value
    }
}

func mix(_ from: Double, _ to: Double, _ progress: Double) -> Double {
    from + (to - from) * progress
}
