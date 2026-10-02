import SwiftUI

@main
struct ShotApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra("Shot", systemImage: state.isRecording ? "stop.circle.fill" : "camera.viewfinder") {
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}
