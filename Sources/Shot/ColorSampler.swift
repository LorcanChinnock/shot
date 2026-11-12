import AppKit
import os
import ShotCore

private let log = Logger.shot("color-sampler")

@MainActor
enum ColorSampler {
    /// Held while the system loupe shows, so only one shows at a time.
    private static var showing: NSColorSampler?
    /// Whether Shot's own loupe is showing.
    private static var picking = false

    /// The colour clicked on screen, in sRGB, or `nil` when Esc cancels or a loupe is already showing. With Screen
    /// Recording allowed it's Shot's loupe from the redesign board, over a still of every display; without it, the system
    /// loupe, which needs no permission. `purpose` says in the hint whether a click copies the colour or picks it.
    static func sample(for purpose: ColorPickerOverlay.Purpose) async -> RGBA? {
        guard showing == nil, !picking else {
            return nil
        }
        if Permissions.hasScreenCapture {
            picking = true
            defer { picking = false }
            do {
                let frozen = try await DisplayCapturer.captureForColorPicking()
                let displays = frozen.map { OverlayDisplay(frame: $0.frame, scale: $0.scale, image: $0.image) }
                return await ColorPickerOverlay.pick(displays: displays, purpose: purpose)
            } catch {
                log.error("Couldn't freeze the screen for Pick Colour, so the system loupe shows: \(error.localizedDescription)")
            }
        }
        return await systemSample()
    }

    private static func systemSample() async -> RGBA? {
        let sampler = NSColorSampler()
        showing = sampler
        defer { showing = nil }
        return await withCheckedContinuation { continuation in
            sampler.show { color in
                continuation.resume(returning: color.map { RGBA($0) })
            }
        }
    }

    /// Whether the system loupe is showing.
    static var isShowing: Bool { showing != nil }

    /// Ends any system loupe still on screen. `NSColorSampler` can't be cancelled, and its loupe lives in a system process
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
