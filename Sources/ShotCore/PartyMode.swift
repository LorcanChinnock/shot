import Foundation

/// The hidden party mode: how it's found and how fast its rainbow turns.
public enum PartyMode {
    /// Clicks on the About page's app icon that reveal the toggle.
    public static let clicksToUnlock = 7
    public static let cycleSeconds: TimeInterval = 6

    /// Where the rainbow is at `time` seconds, as a hue from 0 up to 1.
    public static func hue(at time: TimeInterval) -> Double {
        let phase = (time / cycleSeconds).truncatingRemainder(dividingBy: 1)
        return phase < 0 ? phase + 1 : phase
    }
}
