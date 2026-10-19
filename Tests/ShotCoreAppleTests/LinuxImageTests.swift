import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

// ShotCoreLinux's PNGJPEGCodec in swift:6.3 wrote `linux-shot.png` and `linux-shot.jpg` in Tests/Fixtures, an 8×6
// gradient at scale 2 with every piece of metadata, and `linux-big.jpg`, whose record it split into extended XMP. A file
// written on Linux has to read the same here.

private func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
}

private let record = CaptureRecord(
    original: "Shot 2026-10-20 at 10.00.00.png", kind: "image", created: Date(timeIntervalSince1970: 1_791_640_992), size: .init(width: 4, height: 3), scale: 2,
    source: .init(mode: "window", app: "Notes"), annotations: [CaptureMark(type: "counter", center: [2, 1], text: "Café ✓", number: 1)]
)
private let projectID = "6F9619FF-8B86-D011-B42D-00CF4FC964FF"

@Test(arguments: ["linux-shot.png", "linux-shot.jpg"])
func anImageWrittenOnLinuxReadsBackWithItsScaleAndMetadata(name: String) throws {
    let codec = ImageIOCodec()
    let url = fixture(name)
    #expect(codec.info(ofFileAt: url) == ImageFileInfo(isGIF: false, frames: 1, size: CaptureRecord.Size(width: 8, height: 6)))
    #expect(codec.scale(ofFileAt: url) == 2)
    #expect(codec.record(ofFileAt: url) == record)
    #expect(codec.projectID(ofFileAt: url) == projectID)
    #expect(codec.hasWindowShadow(ofFileAt: url))
    let bitmap = try #require(codec.decode(fileAt: url))
    #expect(bitmap.width == 8 && bitmap.height == 6 && bitmap.scale == 2)
}

@Test func aPNGWrittenOnLinuxHasItsPixels() throws {
    let bitmap = try #require(ImageIOCodec().decode(fileAt: fixture("linux-shot.png")))
    for y in 0 ..< 6 {
        for x in 0 ..< 8 {
            let alpha = 1 - Double(y) / 7, pixel = bitmap[x, y]
            let expected = [Double(x) / 8 * alpha, Double(y) / 6 * alpha, 0.5 * alpha, alpha].map { Int(($0 * 255).rounded()) }
            #expect(zip([pixel.r, pixel.g, pixel.b, pixel.a].map(Int.init), expected).allSatisfy { abs($0 - $1) <= 1 }, "\(x), \(y)")
        }
    }
}

@Test func aRecordLinuxSplitIntoExtendedXMPReadsWhole() {
    let big = CaptureRecord(
        kind: "image", created: Date(timeIntervalSince1970: 1_791_640_992), size: .init(width: 8, height: 6), scale: 1,
        annotations: [CaptureMark(type: "text", text: String(repeating: "Shot ", count: 14_000))]
    )
    #expect(ImageIOCodec().record(ofFileAt: fixture("linux-big.jpg")) == big)
    #expect(ImageIOCodec().projectID(ofFileAt: fixture("linux-big.jpg")) == projectID)
}
