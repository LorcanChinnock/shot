import Observation

@MainActor
@Observable
final class AppState {
    var isRecording = false
    var isPaused = false
    /// Seconds left while a timed screenshot or a recording counts down.
    var countdown: Int?
}
