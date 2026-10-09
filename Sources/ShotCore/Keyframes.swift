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

    /// Sets how the keyframe at `time`, if there is one, eases towards the next.
    public static func settingEasing<V>(_ keyframes: [Keyframe<V>], _ easing: Easing, at time: Double) -> [Keyframe<V>] {
        var result = keyframes
        if let index = index(of: result, at: time) {
            result[index].easing = easing
        }
        return result
    }

    /// Moves the keyframe at `time`, if there is one, to `new`, replacing one already there.
    public static func moving<V>(_ keyframes: [Keyframe<V>], from time: Double, to new: Double) -> [Keyframe<V>] {
        guard let index = index(of: keyframes, at: time) else {
            return keyframes
        }
        var result = keyframes
        var moved = result.remove(at: index)
        result = removing(result, at: new)
        moved.time = new
        result.append(moved)
        result.sort { $0.time < $1.time }
        return result
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

    /// The scale a clip can take, from the canvas handles and the Inspector alike.
    public static let scaleRange = 0.05...20
    /// `scaleRange` in doublings, so a slider gives each doubling equal travel and puts 1× in the middle.
    public static let scaleDoublings = log2(scaleRange.lowerBound)...log2(scaleRange.upperBound)

    public init(position: CGSize = .zero, scale: Double = 1, rotation: Double = 0, opacity: Double = 1, volume: Double = 1, reveal: Double = 1) {
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.volume = volume
        self.reveal = reveal
    }
}

/// One property's value, typed as the property is: a position is a size, everything else a number.
public enum PropertyValue: Equatable, Sendable {
    case size(CGSize)
    case number(Double)

    /// False within a rounding error.
    public func differs(from other: PropertyValue) -> Bool {
        switch (self, other) {
        case let (.size(a), .size(b)): abs(a.width - b.width) > 1e-9 || abs(a.height - b.height) > 1e-9
        case let (.number(a), .number(b)): abs(a - b) > 1e-9
        case (.size, .number), (.number, .size): true
        }
    }
}

extension PropertyValues {
    /// The value of `property`. Setting a value of the wrong type leaves it as it was.
    public subscript(property: AnimatedProperty) -> PropertyValue {
        get {
            switch property {
            case .position: .size(position)
            case .scale: .number(scale)
            case .rotation: .number(rotation)
            case .opacity: .number(opacity)
            case .volume: .number(volume)
            case .reveal: .number(reveal)
            }
        }
        set {
            switch (property, newValue) {
            case let (.position, .size(value)): position = value
            case let (.scale, .number(value)): scale = value
            case let (.rotation, .number(value)): rotation = value
            case let (.opacity, .number(value)): opacity = value
            case let (.volume, .number(value)): volume = value
            case let (.reveal, .number(value)): reveal = value
            case (.position, .number), (.scale, .size), (.rotation, .size), (.opacity, .size), (.volume, .size), (.reveal, .size):
                assertionFailure("\(property) can't hold \(newValue)")
            }
        }
    }
}

/// One property's keyframes, typed as the property is, so `ClipAnimation` can go through its properties in a loop.
public enum PropertyKeyframes: Equatable, Sendable {
    case size([Keyframe<CGSize>])
    case number([Keyframe<Double>])

    public var isEmpty: Bool {
        switch self {
        case let .size(keyframes): keyframes.isEmpty
        case let .number(keyframes): keyframes.isEmpty
        }
    }

    public var times: [Double] {
        switch self {
        case let .size(keyframes): keyframes.map(\.time)
        case let .number(keyframes): keyframes.map(\.time)
        }
    }

    public func hasKeyframe(at time: Double) -> Bool {
        switch self {
        case let .size(keyframes): Keyframes.index(of: keyframes, at: time) != nil
        case let .number(keyframes): Keyframes.index(of: keyframes, at: time) != nil
        }
    }

    /// The easing of the keyframe at `time`, if there is one.
    public func easing(at time: Double) -> Easing? {
        switch self {
        case let .size(keyframes): Keyframes.index(of: keyframes, at: time).map { keyframes[$0].easing }
        case let .number(keyframes): Keyframes.index(of: keyframes, at: time).map { keyframes[$0].easing }
        }
    }

    /// The value at `time`, or `base` with no keyframes.
    public func value(at time: Double, base: PropertyValue) -> PropertyValue {
        switch (self, base) {
        case let (.size(keyframes), .size(base)): .size(Keyframes.value(keyframes, at: time, base: base))
        case let (.number(keyframes), .number(base)): .number(Keyframes.value(keyframes, at: time, base: base))
        case (.size, .number), (.number, .size): base
        }
    }

    /// With the value at `time` set to `value`; a value of the wrong type changes nothing.
    public func setting(at time: Double, to value: PropertyValue) -> PropertyKeyframes {
        switch (self, value) {
        case let (.size(keyframes), .size(value)): .size(Keyframes.setting(keyframes, at: time, to: value))
        case let (.number(keyframes), .number(value)): .number(Keyframes.setting(keyframes, at: time, to: value))
        case (.size, .number), (.number, .size): self
        }
    }

    public func removing(at time: Double) -> PropertyKeyframes {
        switch self {
        case let .size(keyframes): .size(Keyframes.removing(keyframes, at: time))
        case let .number(keyframes): .number(Keyframes.removing(keyframes, at: time))
        }
    }

    public func shifted(by delta: Double) -> PropertyKeyframes {
        switch self {
        case let .size(keyframes): .size(Keyframes.shifted(keyframes, by: delta))
        case let .number(keyframes): .number(Keyframes.shifted(keyframes, by: delta))
        }
    }

    public func splitting(at time: Double) -> (before: PropertyKeyframes, after: PropertyKeyframes) {
        switch self {
        case let .size(keyframes):
            let (before, after) = Keyframes.splitting(keyframes, at: time)
            return (.size(before), .size(after))
        case let .number(keyframes):
            let (before, after) = Keyframes.splitting(keyframes, at: time)
            return (.number(before), .number(after))
        }
    }

    public func settingEasing(_ easing: Easing, at time: Double) -> PropertyKeyframes {
        switch self {
        case let .size(keyframes): .size(Keyframes.settingEasing(keyframes, easing, at: time))
        case let .number(keyframes): .number(Keyframes.settingEasing(keyframes, easing, at: time))
        }
    }

    public func moving(from time: Double, to new: Double) -> PropertyKeyframes {
        switch self {
        case let .size(keyframes): .size(Keyframes.moving(keyframes, from: time, to: new))
        case let .number(keyframes): .number(Keyframes.moving(keyframes, from: time, to: new))
        }
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

    /// The keyframes of `property`: the one place that names each property's storage. Setting keyframes of the wrong
    /// type leaves them as they were.
    public subscript(property: AnimatedProperty) -> PropertyKeyframes {
        get {
            switch property {
            case .position: .size(position)
            case .scale: .number(scale)
            case .rotation: .number(rotation)
            case .opacity: .number(opacity)
            case .volume: .number(volume)
            case .reveal: .number(reveal)
            }
        }
        set {
            switch (property, newValue) {
            case let (.position, .size(keyframes)): position = keyframes
            case let (.scale, .number(keyframes)): scale = keyframes
            case let (.rotation, .number(keyframes)): rotation = keyframes
            case let (.opacity, .number(keyframes)): opacity = keyframes
            case let (.volume, .number(keyframes)): volume = keyframes
            case let (.reveal, .number(keyframes)): reveal = keyframes
            case (.position, .number), (.scale, .size), (.rotation, .size), (.opacity, .size), (.volume, .size), (.reveal, .size):
                assertionFailure("\(property) can't hold \(newValue)")
            }
        }
    }

    /// Applies `change` to each property's keyframes.
    private func mapped(_ change: (PropertyKeyframes) -> PropertyKeyframes) -> ClipAnimation {
        var result = self
        for property in AnimatedProperty.allCases {
            result[property] = change(self[property])
        }
        return result
    }

    public var isEmpty: Bool {
        AnimatedProperty.allCases.allSatisfy { self[$0].isEmpty }
    }

    /// Every time that has a keyframe of any property, in order.
    public var times: [Double] {
        let all = AnimatedProperty.allCases.flatMap { self[$0].times }.sorted()
        return all.reduce(into: []) { result, time in
            if result.last.map({ abs($0 - time) > Keyframes.tolerance }) ?? true {
                result.append(time)
            }
        }
    }

    public func hasKeyframes(_ property: AnimatedProperty) -> Bool {
        !self[property].isEmpty
    }

    public func hasKeyframe(_ property: AnimatedProperty, at time: Double) -> Bool {
        self[property].hasKeyframe(at: time)
    }

    /// The values at `time`, with `base` for any property that has no keyframes.
    public func values(at time: Double, base: PropertyValues) -> PropertyValues {
        var result = base
        for property in AnimatedProperty.allCases {
            result[property] = self[property].value(at: time, base: base[property])
        }
        return result
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
        self[property] = self[property].removing(at: time)
    }

    /// Takes away every keyframe at `time`.
    public func removingKeyframes(at time: Double) -> ClipAnimation {
        mapped { $0.removing(at: time) }
    }

    public mutating func set(_ property: AnimatedProperty, at time: Double, to values: PropertyValues) {
        self[property] = self[property].setting(at: time, to: values[property])
    }

    /// Sets how the keyframes at `time` ease towards the next.
    public func settingEasing(_ easing: Easing, at time: Double) -> ClipAnimation {
        mapped { $0.settingEasing(easing, at: time) }
    }

    /// The easing of a keyframe at `time`, if there is one.
    public func easing(at time: Double) -> Easing? {
        AnimatedProperty.allCases.lazy.compactMap { self[$0].easing(at: time) }.first
    }

    /// Moves every keyframe at `time` to `new`.
    public func movingKeyframes(from time: Double, to new: Double) -> ClipAnimation {
        mapped { $0.moving(from: time, to: new) }
    }

    public func shifted(by delta: Double) -> ClipAnimation {
        mapped { $0.shifted(by: delta) }
    }

    /// The animation of the part of a clip before `time`, and of the part after it with times counted from the cut.
    public func splitting(at time: Double) -> (before: ClipAnimation, after: ClipAnimation) {
        var before = self, after = self
        for property in AnimatedProperty.allCases {
            (before[property], after[property]) = self[property].splitting(at: time)
        }
        return (before, after)
    }

    /// Takes the keyframes of `property` in `other`.
    public func replacing(_ property: AnimatedProperty, with other: ClipAnimation) -> ClipAnimation {
        var result = self
        result[property] = other[property]
        return result
    }
}
