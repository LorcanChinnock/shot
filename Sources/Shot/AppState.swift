import Observation

@MainActor
@Observable
final class AppState {
    var isRecording = false {
        didSet { menuBar.recordingChanged(isRecording && !isPaused) }
    }

    var isPaused = false {
        didSet { menuBar.recordingChanged(isRecording && !isPaused) }
    }

    /// Whole seconds recorded, for the timer in the menu bar; nil when nothing is recording.
    var recordingSeconds: Int?

    /// Seconds left while a timed screenshot or a recording counts down.
    var countdown: Int? {
        didSet { menuBar.countdownChanged(from: oldValue, to: countdown) }
    }

    /// The menu bar icon's flip and pulse.
    let menuBar = MenuBarAnimation()
}
