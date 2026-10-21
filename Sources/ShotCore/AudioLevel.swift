import Foundation

/// Maps microphone loudness to how full a level meter is.
public enum AudioLevel {
    /// Quieter than this, in decibels below full scale, shows as silence.
    public static let floor: Float = -50

    /// `samples` are in -1...1.
    public static func rms(_ samples: some Collection<Float>) -> Float {
        guard !samples.isEmpty else {
            return 0
        }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    /// From 0 at `floor` to 1 at full scale, linear in decibels.
    public static func meter(rms: Float) -> Double {
        guard rms > 0 else {
            return 0
        }
        let decibels = 20 * log10(rms)
        return Double(min(max((decibels - floor) / -floor, 0), 1))
    }
}
