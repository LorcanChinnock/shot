import AppKit
import os
import ShotCore

private let log = Logger.shot("color-sampler")

@MainActor
enum ColorSampler {
    /// Held while the loupe shows, so only one shows at a time.
    private static var showing: NSColorSampler?

    /// Shows the system loupe and returns the colour clicked, in sRGB, or `nil` when Esc cancels or a loupe is
    /// already showing. Needs no permission.
    static func sample() async -> RGBA? {
        guard showing == nil else {
            return nil
        }
        let sampler = NSColorSampler()
        showing = sampler
        defer { showing = nil }
        return await withCheckedContinuation { continuation in
            sampler.show { color in
                continuation.resume(returning: color.map { RGBA($0) })
            }
        }
    }

    /// Whether a loupe of ours is showing.
    static var isShowing: Bool { showing != nil }

    /// Ends any loupe still on screen. `NSColorSampler` can't be cancelled, and its loupe lives in a system process
    /// that outlives a client that quits or dies mid-pick, so it keeps swallowing every click on the desktop until
    /// it's killed. The system starts the process again on the next pick.
    nonisolated static func endLoupe() {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-9", "-x", "ColorSampler"]
        do {
            try pkill.run()
            pkill.waitUntilExit()
            if pkill.terminationStatus == 0 {
                log.notice("Ended a loupe left showing")
            }
        } catch {
            log.error("Couldn't end a loupe left showing: \(error.localizedDescription)")
        }
    }
}
