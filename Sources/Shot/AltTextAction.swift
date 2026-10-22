import AppKit
import OSLog
import ShotCore

/// **Copy Alt Text**: describes a screenshot with Apple's on-device model and copies it. Shown only on a Mac whose model
/// can see images (macOS 27), and only run when chosen.
@MainActor
enum AltTextAction {
    private static let log = Logger.shot("alt-text")

    static var isAvailable: Bool { AltText.isAvailable }

    static func copy(imageAt url: URL) async {
        guard let image = ImageCodec.image(at: url) else {
            Toast.error("Couldn't read \(url.lastPathComponent)")
            return
        }
        await copy(image)
    }

    static func copy(_ image: CGImage) async {
        guard #available(macOS 27, *) else {
            return
        }
        Toast.progress("Writing alt text…")
        let sendable = SendableImage(image)
        do {
            let text = try await Task.detached { try await AltText.describe(sendable.image) }.value
            guard !text.isEmpty else {
                Toast.error("Couldn't write alt text for this image")
                return
            }
            Clipboard.copy(string: text)
            Toast.show("Copied alt text")
        } catch {
            log.error("Alt text failed: \(error.localizedDescription, privacy: .public)")
            Toast.error("Couldn't write alt text: \(error.localizedDescription)")
        }
    }
}
