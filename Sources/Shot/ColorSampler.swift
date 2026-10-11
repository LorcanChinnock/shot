import AppKit
import ShotCore

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
}
