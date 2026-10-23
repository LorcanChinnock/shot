import AppKit
import OSLog
import ShotCore

/// **Copy Bug Report**: turns a capture or recording into Markdown repro steps and copies them. Uses the provider set
/// up in Settings, or Apple's on-device model on macOS 27; only runs when chosen.
@MainActor
enum BugReportAction {
    private static let log = Logger.shot("bug-report")

    static var isAvailable: Bool { BugReporter.onDeviceAvailable || Preferences().chatProvider != nil }

    static func copy(fileAt url: URL) async {
        await copy { provider in try await BugReporter.report(for: url, provider: provider) }
    }

    static func copy(_ image: CGImage) async {
        let sendable = SendableImage(image)
        await copy { provider in try await BugReporter.report(for: sendable.image, provider: provider) }
    }

    private static func copy(_ make: @escaping @Sendable (ChatProvider?) async throws -> String) async {
        let provider = Preferences().chatProvider
        guard provider != nil || BugReporter.onDeviceAvailable else {
            return
        }
        Toast.progress("Writing bug report…")
        do {
            let markdown = try await Task.detached { try await make(provider) }.value
            Clipboard.copy(string: markdown)
            Toast.show("Copied bug report")
        } catch {
            log.error("Bug report failed: \(error.localizedDescription, privacy: .public)")
            Toast.error("Couldn't write a bug report: \(error.localizedDescription)")
        }
    }
}
