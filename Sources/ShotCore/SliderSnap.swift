import Foundation

/// How a slider with a default holds on to it, so getting back to the default is easy.
public enum SliderSnap {
    /// The value a drag to `value` sets: `target` when it's within `threshold` (a fraction of the range) of it, else
    /// `value` unchanged. No target, or no range, never snaps.
    public static func value(_ value: Double, default target: Double?, in range: ClosedRange<Double>, threshold: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard let target, span > 0, abs(value - target) <= threshold * span else {
            return value
        }
        return target
    }

    /// The value a step from `from` to `to` sets: `target` when the step would pass over it, so stepping lands on the
    /// default on the way through even when it's between the steps. A step from the default, or that stops short of it,
    /// goes where it was going.
    public static func stepping(from: Double, to: Double, default target: Double?) -> Double {
        guard let target, min(from, to) < target, target < max(from, to) else {
            return to
        }
        return target
    }
}
