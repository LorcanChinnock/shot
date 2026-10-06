import CoreGraphics
import Foundation

/// How a value eases from one keyframe to the next.
public enum Easing: String, Codable, CaseIterable, Sendable {
    case linear, easeIn, easeOut, easeInOut, spring

    public var title: String {
        switch self {
        case .linear: "Linear"
        case .easeIn: "Ease in"
        case .easeOut: "Ease out"
        case .easeInOut: "Ease in-out"
        case .spring: "Spring"
        }
    }

    /// How far along the move from 0 to 1 a fraction `t` of the time has got; 0 at 0 and 1 at 1. A spring overshoots on the way.
    public func progress(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .spring:
            // A damped oscillation of one and a half turns, scaled so it ends exactly on 1.
            let raw = { (x: Double) in 1 - exp(-6 * x) * cos(3 * .pi * x) }
            return raw(t) / raw(1)
        }
    }
}

public protocol Interpolatable {
    static func interpolate(_ from: Self, _ to: Self, _ fraction: Double) -> Self
}

extension Double: Interpolatable {
    public static func interpolate(_ from: Double, _ to: Double, _ fraction: Double) -> Double {
        from + (to - from) * fraction
    }
}

extension CGSize: Interpolatable {
    public static func interpolate(_ from: CGSize, _ to: CGSize, _ fraction: Double) -> CGSize {
        CGSize(width: Double.interpolate(from.width, to.width, fraction), height: Double.interpolate(from.height, to.height, fraction))
    }
}

/// A value at a time, in seconds from the start of its clip; `easing` shapes the move to the next keyframe.
public struct Keyframe<Value: Interpolatable & Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var time: Double
    public var value: Value
    public var easing: Easing

    public init(time: Double, value: Value, easing: Easing = .linear) {
        self.time = time
        self.value = value
        self.easing = easing
    }
}

public enum Keyframes {
    /// Keyframes closer in time than this are the same one.
    public static let tolerance = 1.0 / 600

    /// The value at `time`: `base` with no keyframes, the first or last one's outside them, and between two the first's
    /// value eased towards the second's.
    public static func value<V>(_ keyframes: [Keyframe<V>], at time: Double, base: V) -> V {
        guard let first = keyframes.first, let last = keyframes.last else {
            return base
        }
        if time <= first.time {
            return first.value
        }
        if time >= last.time {
            return last.value
        }
        let index = keyframes.lastIndex { $0.time <= time } ?? 0
        let from = keyframes[index], to = keyframes[index + 1]
        let fraction = (time - from.time) / (to.time - from.time)
        return V.interpolate(from.value, to.value, from.easing.progress(fraction))
    }

    public static func index<V>(of keyframes: [Keyframe<V>], at time: Double) -> Int? {
        keyframes.firstIndex { abs($0.time - time) <= tolerance }
    }

    /// Sets the value at `time`, keeping the easing of a keyframe already there.
    public static func setting<V>(_ keyframes: [Keyframe<V>], at time: Double, to value: V) -> [Keyframe<V>] {
        var result = keyframes
        if let existing = index(of: result, at: time) {
            result[existing].value = value
        } else {
            result.append(Keyframe(time: time, value: value))
            result.sort { $0.time < $1.time }
        }
        return result
    }

    public static func removing<V>(_ keyframes: [Keyframe<V>], at time: Double) -> [Keyframe<V>] {
        keyframes.filter { abs($0.time - time) > tolerance }
    }

    public static func shifted<V>(_ keyframes: [Keyframe<V>], by delta: Double) -> [Keyframe<V>] {
        keyframes.map { Keyframe(time: $0.time + delta, value: $0.value, easing: $0.easing) }
    }

    /// The keyframes of the first part, and of the second with its times counted from the cut, each holding the value
    /// the curve has at the cut so the move carries on across it.
    public static func splitting<V>(_ keyframes: [Keyframe<V>], at time: Double) -> (before: [Keyframe<V>], after: [Keyframe<V>]) {
        guard !keyframes.isEmpty else {
            return ([], [])
        }
        let held = value(keyframes, at: time, base: keyframes[0].value)
        let easing = keyframes.last { $0.time < time }?.easing ?? .linear
        var before = keyframes.filter { $0.time < time - tolerance }
        var after = keyframes.filter { $0.time > time + tolerance }.map { Keyframe(time: $0.time - time, value: $0.value, easing: $0.easing) }
        before.append(Keyframe(time: time, value: held, easing: easing))
        after.insert(Keyframe(time: 0, value: held, easing: easing), at: 0)
        return (before, after)
    }
}

/// What a clip can animate.
public enum AnimatedProperty: String, Codable, CaseIterable, Sendable {
    case position, scale, rotation, opacity, volume
    /// How much of an arrow or pen stroke is drawn.
    case reveal
}

/// The animated values of a clip at one moment.
public struct PropertyValues: Equatable, Sendable {
    public var position: CGSize
    public var scale: Double
    public var rotation: Double
    public var opacity: Double
    public var volume: Double
    public var reveal: Double

    public init(position: CGSize = .zero, scale: Double = 1, rotation: Double = 0, opacity: Double = 1, volume: Double = 1, reveal: Double = 1) {
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.volume = volume
        self.reveal = reveal
    }
}

/// Keyframes for each property of a clip, in seconds from the clip's start. A property with none keeps its plain value.
public struct ClipAnimation: Codable, Equatable, Sendable {
    public var position: [Keyframe<CGSize>] = []
    public var scale: [Keyframe<Double>] = []
    public var rotation: [Keyframe<Double>] = []
    public var opacity: [Keyframe<Double>] = []
    public var volume: [Keyframe<Double>] = []
    public var reveal: [Keyframe<Double>] = []

    public init() {}

    public var isEmpty: Bool {
        position.isEmpty && scale.isEmpty && rotation.isEmpty && opacity.isEmpty && volume.isEmpty && reveal.isEmpty
    }

    /// Every time that has a keyframe of any property, in order.
    public var times: [Double] {
        var all = position.map(\.time) + scale.map(\.time) + rotation.map(\.time) + opacity.map(\.time) + volume.map(\.time) + reveal.map(\.time)
        all.sort()
        return all.reduce(into: []) { result, time in
            if result.last.map({ abs($0 - time) > Keyframes.tolerance }) ?? true {
                result.append(time)
            }
        }
    }

    public func hasKeyframes(_ property: AnimatedProperty) -> Bool {
        switch property {
        case .position: !position.isEmpty
        case .scale: !scale.isEmpty
        case .rotation: !rotation.isEmpty
        case .opacity: !opacity.isEmpty
        case .volume: !volume.isEmpty
        case .reveal: !reveal.isEmpty
        }
    }

    public func hasKeyframe(_ property: AnimatedProperty, at time: Double) -> Bool {
        switch property {
        case .position: Keyframes.index(of: position, at: time) != nil
        case .scale: Keyframes.index(of: scale, at: time) != nil
        case .rotation: Keyframes.index(of: rotation, at: time) != nil
        case .opacity: Keyframes.index(of: opacity, at: time) != nil
        case .volume: Keyframes.index(of: volume, at: time) != nil
        case .reveal: Keyframes.index(of: reveal, at: time) != nil
        }
    }

    /// The values at `time`, with `base` for any property that has no keyframes.
    public func values(at time: Double, base: PropertyValues) -> PropertyValues {
        PropertyValues(
            position: Keyframes.value(position, at: time, base: base.position),
            scale: Keyframes.value(scale, at: time, base: base.scale),
            rotation: Keyframes.value(rotation, at: time, base: base.rotation),
            opacity: Keyframes.value(opacity, at: time, base: base.opacity),
            volume: Keyframes.value(volume, at: time, base: base.volume),
            reveal: Keyframes.value(reveal, at: time, base: base.reveal)
        )
    }

    /// Adds a keyframe of `property` at `time` holding what it is there now, or takes the one that's there away.
    public func togglingKeyframe(_ property: AnimatedProperty, at time: Double, current: PropertyValues) -> ClipAnimation {
        var result = self
        if hasKeyframe(property, at: time) {
            result.remove(property, at: time)
        } else {
            result.set(property, at: time, to: current)
        }
        return result
    }

    public mutating func remove(_ property: AnimatedProperty, at time: Double) {
        switch property {
        case .position: position = Keyframes.removing(position, at: time)
        case .scale: scale = Keyframes.removing(scale, at: time)
        case .rotation: rotation = Keyframes.removing(rotation, at: time)
        case .opacity: opacity = Keyframes.removing(opacity, at: time)
        case .volume: volume = Keyframes.removing(volume, at: time)
        case .reveal: reveal = Keyframes.removing(reveal, at: time)
        }
    }

    /// Takes away every keyframe at `time`.
    public func removingKeyframes(at time: Double) -> ClipAnimation {
        var result = self
        for property in AnimatedProperty.allCases {
            result.remove(property, at: time)
        }
        return result
    }

    public mutating func set(_ property: AnimatedProperty, at time: Double, to values: PropertyValues) {
        switch property {
        case .position: position = Keyframes.setting(position, at: time, to: values.position)
        case .scale: scale = Keyframes.setting(scale, at: time, to: values.scale)
        case .rotation: rotation = Keyframes.setting(rotation, at: time, to: values.rotation)
        case .opacity: opacity = Keyframes.setting(opacity, at: time, to: values.opacity)
        case .volume: volume = Keyframes.setting(volume, at: time, to: values.volume)
        case .reveal: reveal = Keyframes.setting(reveal, at: time, to: values.reveal)
        }
    }

    /// Sets how the keyframes at `time` ease towards the next.
    public func settingEasing(_ easing: Easing, at time: Double) -> ClipAnimation {
        var result = self
        func apply<V>(_ keyframes: inout [Keyframe<V>]) {
            if let index = Keyframes.index(of: keyframes, at: time) {
                keyframes[index].easing = easing
            }
        }
        apply(&result.position)
        apply(&result.scale)
        apply(&result.rotation)
        apply(&result.opacity)
        apply(&result.volume)
        apply(&result.reveal)
        return result
    }

    /// The easing of a keyframe at `time`, if there is one.
    public func easing(at time: Double) -> Easing? {
        position.first { abs($0.time - time) <= Keyframes.tolerance }?.easing
            ?? scale.first { abs($0.time - time) <= Keyframes.tolerance }?.easing
            ?? rotation.first { abs($0.time - time) <= Keyframes.tolerance }?.easing
            ?? opacity.first { abs($0.time - time) <= Keyframes.tolerance }?.easing
            ?? volume.first { abs($0.time - time) <= Keyframes.tolerance }?.easing
            ?? reveal.first { abs($0.time - time) <= Keyframes.tolerance }?.easing
    }

    /// Moves every keyframe at `time` to `new`.
    public func movingKeyframes(from time: Double, to new: Double) -> ClipAnimation {
        var result = self
        func apply<V>(_ keyframes: inout [Keyframe<V>]) {
            guard let index = Keyframes.index(of: keyframes, at: time) else {
                return
            }
            var moved = keyframes[index]
            keyframes.remove(at: index)
            keyframes = Keyframes.removing(keyframes, at: new)
            moved.time = new
            keyframes.append(moved)
            keyframes.sort { $0.time < $1.time }
        }
        apply(&result.position)
        apply(&result.scale)
        apply(&result.rotation)
        apply(&result.opacity)
        apply(&result.volume)
        apply(&result.reveal)
        return result
    }

    public func shifted(by delta: Double) -> ClipAnimation {
        var result = self
        result.position = Keyframes.shifted(position, by: delta)
        result.scale = Keyframes.shifted(scale, by: delta)
        result.rotation = Keyframes.shifted(rotation, by: delta)
        result.opacity = Keyframes.shifted(opacity, by: delta)
        result.volume = Keyframes.shifted(volume, by: delta)
        result.reveal = Keyframes.shifted(reveal, by: delta)
        return result
    }

    /// The animation of the part of a clip before `time`, and of the part after it with times counted from the cut.
    public func splitting(at time: Double) -> (before: ClipAnimation, after: ClipAnimation) {
        var before = self, after = self
        (before.position, after.position) = Keyframes.splitting(position, at: time)
        (before.scale, after.scale) = Keyframes.splitting(scale, at: time)
        (before.rotation, after.rotation) = Keyframes.splitting(rotation, at: time)
        (before.opacity, after.opacity) = Keyframes.splitting(opacity, at: time)
        (before.volume, after.volume) = Keyframes.splitting(volume, at: time)
        (before.reveal, after.reveal) = Keyframes.splitting(reveal, at: time)
        return (before, after)
    }

    /// Takes the keyframes of `property` in `other`.
    public func replacing(_ property: AnimatedProperty, with other: ClipAnimation) -> ClipAnimation {
        var result = self
        switch property {
        case .position: result.position = other.position
        case .scale: result.scale = other.scale
        case .rotation: result.rotation = other.rotation
        case .opacity: result.opacity = other.opacity
        case .volume: result.volume = other.volume
        case .reveal: result.reveal = other.reveal
        }
        return result
    }
}
