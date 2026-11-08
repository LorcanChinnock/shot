import Foundation

/// The recording timer the controls and the menu bar show: whole seconds that have run, leaving out pauses.
public enum RecordingClock {
    /// Whole seconds in `elapsed`. A second shows only once it has fully passed, so the timer reads 0:00 as it starts.
    public static func seconds(_ elapsed: TimeInterval) -> Int {
        max(Int(elapsed.rounded(.down)), 0)
    }

    /// "0:07", "12:34", or "1:02:03" past an hour.
    public static func label(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    /// The label with every digit a zero, and never shorter than "00:00". Drawn hidden behind the timer in tabular figures,
    /// it holds the timer's width, so the bar keeps its size until the recording passes an hour.
    public static func placeholder(_ label: String) -> String {
        let zeroed = String(label.map { $0.isNumber ? "0" : $0 })
        return zeroed.count < 5 ? "00:00" : zeroed
    }

    /// How long to wait from `elapsed` until the next whole second, plus a little so the tick lands just past it.
    public static func untilNextSecond(_ elapsed: TimeInterval) -> TimeInterval {
        let fraction = elapsed - elapsed.rounded(.down)
        return 1 - fraction + 0.01
    }
}
