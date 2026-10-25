import SwiftUI

@main
struct MugCoApp: App {
    var body: some Scene {
        // A fixed size, so every capture of it has the same framing.
        Window("Mug Co. Support", id: "main") {
            InboxView()
                .frame(width: 960, height: 600)
        }
        .windowResizability(.contentSize)
    }
}
