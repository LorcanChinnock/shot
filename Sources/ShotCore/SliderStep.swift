import Foundation

/// The value an arrow key moves a slider to: the next mark on a grid of `fraction` of the range, up or down, so a value
/// between marks lands on one and repeated steps stay on whole percentages. Clamped to the range.
public enum SliderStep {
    public static func value(_ value: Double, up: Bool, fraction: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0, fraction > 0 else {
            return range.lowerBound
        }
        let position = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span / fraction
        // The tolerance keeps a value on a mark, give or take rounding, from counting as between marks.
        let mark = up ? (position + 1e-9).rounded(.down) + 1 : (position - 1e-9).rounded(.up) - 1
        return min(max(range.lowerBound + mark * fraction * span, range.lowerBound), range.upperBound)
    }
}
