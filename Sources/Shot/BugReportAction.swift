import AppKit
import OSLog
import ShotCore

/// **Copy Bug Report**: turns a capture or recording into Markdown repro steps and copies them. Uses Apple's on-device
/// model, so it needs macOS 27; only runs when chosen.
@MainActor
enum BugReportAction {
    private static let log = Logger.shot("bug-report")

    static var isAvailable: Bool { BugReporter.onDeviceAvailable }

    static func copy(fileAt url: URL) async {
        await copy { try await BugReporter.report(for: url) }
    }

    static func copy(_ image: CGImage) async {
        let sendable = SendableImage(image)
        await copy { try await BugReporter.report(for: sendable.image) }
    }

    private static var writing: Task<String, Error>?

    private static func copy(_ make: @escaping @Sendable () async throws -> String) async {
        guard BugReporter.onDeviceAvailable else {
            Toast.error("Turn on Apple Intelligence in System Settings to write bug reports.")
            return
        }
        guard writing == nil else {
            Toast.error("A bug report is already being written")
            return
        }
        // Apple's on-device model can take most of a minute, so say so and let the wait be cancelled.
        let work = Task.detached { try await make() }
        writing = work
        defer { writing = nil }
        let cancel: @MainActor @Sendable () -> Void = { work.cancel() }
        Toast.show("Writing bug report… this can take a minute", duration: nil, cancel: cancel)
        do {
            let markdown = try await work.value
            Clipboard.copy(string: markdown)
            Toast.show("Copied bug report")
        } catch where work.isCancelled {
            Toast.show("Bug report cancelled")
        } catch {
            log.error("Bug report failed: \(error.localizedDescription, privacy: .public)")
            Toast.error("Couldn't write a bug report: \(error.localizedDescription)")
        }
    }
}
