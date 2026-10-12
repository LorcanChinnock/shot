/// A screenshot taken after a countdown, which catches menus and hover states that a click or a shortcut would close.
public enum ScreenshotTimer {
    /// The delays the menu offers, in seconds: the recording countdown's lengths.
    public static let delays = RecordingStart.countdowns.filter { $0 > 0 }
    /// What `shot://capture-timer` waits when it has no `seconds`.
    public static let defaultDelay = 5
    /// The seconds `shot://capture-timer?seconds=` accepts.
    public static let urlDelays = 1...60
}
