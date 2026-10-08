/// What happens once the area to record is picked: show the setup panel or not, then count down or start at once.
public struct RecordingStart: Equatable, Sendable {
    /// The countdown lengths Settings offers, in seconds; 0 is off.
    public static let countdowns = [0, 3, 5]

    public let showsSetup: Bool
    /// Seconds to count down before recording starts; 0 starts at once.
    public let countdown: Int

    public init(showsSetup: Bool, countdown: Int) {
        self.showsSetup = showsSetup
        self.countdown = countdown
    }

    /// Holding ⌥ when the pick ends opens the setup panel for that one recording.
    public static func after(adjustBeforeRecording: Bool, countdown: Int, optionHeld: Bool) -> RecordingStart {
        RecordingStart(showsSetup: adjustBeforeRecording || optionHeld, countdown: countdowns.contains(countdown) ? countdown : 0)
    }
}
