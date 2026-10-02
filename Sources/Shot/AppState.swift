import Observation

@MainActor
@Observable
final class AppState {
    var isRecording = false
    var isPaused = false
}
