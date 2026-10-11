import AppKit
import ShotCore

@MainActor
enum ColorSampler {
    /// Shows the system loupe and returns the colour clicked, in sRGB, or `nil` when Esc cancels. Needs no permission.
    static func sample() async -> RGBA? {
        await withCheckedContinuation { continuation in
            NSColorSampler().show { color in
                continuation.resume(returning: color.map { RGBA($0) })
            }
        }
    }
}
