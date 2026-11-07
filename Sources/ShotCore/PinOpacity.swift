import Foundation

/// How see-through a pinned capture is, from its bar's slider or the arrow keys. A pin starts solid and never fades below
/// `minimum`, so it can't vanish while it still takes up the screen.
public enum PinOpacity {
    public static let full = 1.0
    public static let minimum = 0.2
    /// What one press of ↑ or ↓ moves it by.
    public static let step = 0.1

    public static var range: ClosedRange<Double> { minimum...full }

    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else {
            return full
        }
        return min(max(value, minimum), full)
    }

    /// The whole percentage the bar shows, "Pinned · 80%".
    public static func percent(_ value: Double) -> Int {
        Int((clamped(value) * 100).rounded())
    }

    /// One `step` up or down, landing on the next whole step, so 83% goes up to 90% and down to 80%.
    public static func stepped(_ value: Double, up: Bool) -> Double {
        let steps = clamped(value) / step
        // A small tolerance keeps 0.8, stored as 7.999… steps, on its own step rather than a step below it.
        let next = up ? (steps + 1e-6).rounded(.down) + 1 : (steps - 1e-6).rounded(.up) - 1
        return clamped((next * step * 100).rounded() / 100)
    }
}
