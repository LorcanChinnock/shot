import Foundation

/// The ring on the countdown panel (#1078), which empties as the seconds run out. At each tick it shows the seconds left
/// as a share of the whole countdown, then drains a second's worth while that second passes, so it reaches empty as the
/// capture is taken.
public enum CountdownRing {
    /// How full the ring is with `remaining` of `total` seconds left, from 0 to 1.
    public static func fraction(remaining: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(remaining) / Double(total), 0), 1)
    }

    /// Where the ring drains to over the second that starts with `remaining` left: one second less.
    public static func target(remaining: Int, of total: Int) -> Double {
        fraction(remaining: remaining - 1, of: total)
    }
}
