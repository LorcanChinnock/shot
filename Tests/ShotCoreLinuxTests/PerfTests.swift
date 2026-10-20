import Foundation
import Testing
@testable import ShotCoreLinux

/// Times what Linux does in plain Swift where a Mac has Core Image, against budgets in `docs/performance.md`. Unlike the
/// Mac's PerfTests, it runs with the other Linux tests on every pull request, so it keeps the fastest of only a few runs.
@Suite(.serialized) struct PerfTests {
    @Test func blurringA2560By1600CaptureStaysInBudget() throws {
        let capture = BitmapImage(try gradient(width: 2560, height: 1600))
        let effects = PortableEffects()
        var fastest = Duration.seconds(Int64.max)
        for _ in 0..<3 {
            fastest = min(fastest, try ContinuousClock().measure {
                _ = try #require(effects.blurred(capture, radius: 20))
            })
        }
        let budget = Duration.milliseconds(2500)
        print("Blur 2560×1600: \(fastest), budget \(budget)")
        #expect(fastest <= budget, "Blur took \(fastest), over its \(budget) budget")
    }
}

/// Opaque, with detail in every channel.
private func gradient(width: Int, height: Int) throws -> Bitmap {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            (pixels[i], pixels[i + 1], pixels[i + 2]) = (UInt8(x * 255 / width), UInt8(y * 255 / height), UInt8((x + y) % 256))
        }
    }
    return try #require(Bitmap(width: width, height: height, pixels: Data(pixels)))
}
