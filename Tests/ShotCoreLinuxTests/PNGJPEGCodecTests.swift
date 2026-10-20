import Foundation
import Testing
@testable import ShotCoreLinux

// Tests/Fixtures holds files from three places. ImageIOCodec on macOS wrote `mac-shot.png` and `mac-shot.jpg`, an 8×6
// gradient at scale 2 with every piece of metadata, `mac-plain.png` with none and `mac-big.jpg` with a record ImageIO
// splits into extended XMP. This codec in swift:6.3 wrote `linux-shot.png`, `linux-shot.jpg` and `linux-big.jpg` the
// same way, which ShotCoreAppleTests' LinuxImageTests reads back through ImageIOCodec. Python's zlib wrote `gray.png`
// and `gray-alpha.png`.

private func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
}

private let record = CaptureRecord(
    original: "Shot 2026-10-20 at 10.00.00.png", kind: "image", created: Date(timeIntervalSince1970: 1_791_640_992), size: .init(width: 4, height: 3), scale: 2,
    source: .init(mode: "window", app: "Notes"), annotations: [CaptureMark(type: "counter", center: [2, 1], text: "Café ✓", number: 1)]
)
private let projectID = "6F9619FF-8B86-D011-B42D-00CF4FC964FF"
private let bigRecord = CaptureRecord(
    kind: "image", created: Date(timeIntervalSince1970: 1_791_640_992), size: .init(width: 8, height: 6), scale: 1,
    annotations: [CaptureMark(type: "text", text: String(repeating: "Shot ", count: 14_000))]
)

/// The straight red, green, blue and alpha of the fixtures' gradient at `x`, `y`, as the Mac test drew it.
private func gradientColor(x: Int, y: Int, width: Int = 8, height: Int = 6) -> (r: Double, g: Double, b: Double, a: Double) {
    (Double(x) / Double(width), Double(y) / Double(height), 0.5, 1 - Double(y) / Double(height + 1))
}

/// The gradient as a premultiplied `Bitmap`, every pixel different, alpha falling from opaque at the top.
private func gradient(width: Int, height: Int, scale: CGFloat = 1, opaque: Bool = false) throws -> Bitmap {
    var pixels = Data()
    for y in 0 ..< height {
        for x in 0 ..< width {
            let color = gradientColor(x: x, y: y, width: width, height: height)
            let alpha = opaque ? 1 : color.a
            pixels += [color.r, color.g, color.b].map { UInt8(($0 * alpha * 255).rounded()) } + [UInt8((alpha * 255).rounded())]
        }
    }
    return try #require(Bitmap(width: width, height: height, scale: scale, pixels: pixels))
}

private func temporaryFile(_ format: ImageFormat) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("codec-\(UUID().uuidString).\(format.fileExtension)")
}

/// Whether every byte of `a` is within `tolerance` of `b`'s.
private func close(_ a: Bitmap, _ b: Bitmap, within tolerance: Int) -> Bool {
    a.width == b.width && a.height == b.height && zip(a.pixels, b.pixels).allSatisfy { abs(Int($0) - Int($1)) <= tolerance }
}

@Test(arguments: [CGFloat(1), 2])
func anRGBAPNGRoundTripsToTheSamePixels(scale: CGFloat) throws {
    let codec = PNGJPEGCodec()
    let bitmap = try gradient(width: 33, height: 17, scale: scale)
    let data = try #require(codec.encode(bitmap, as: .png, quality: 1, metadata: ImageMetadata()))
    #expect(codec.decode(data) == bitmap)
}

@Test func aGreyscalePNGDecodesToGreyRGBA() throws {
    let codec = PNGJPEGCodec()
    let gray = try #require(codec.decode(fileAt: fixture("gray.png")))
    #expect(gray.width == 3 && gray.height == 2 && gray.scale == 1)
    #expect(gray[0, 0] == (0, 0, 0, 255) && gray[1, 0] == (128, 128, 128, 255) && gray[2, 1] == (32, 32, 32, 255))
    let withAlpha = try #require(codec.decode(fileAt: fixture("gray-alpha.png")))
    #expect(withAlpha[0, 0] == (255, 255, 255, 255))
    #expect(withAlpha[1, 0] == (128, 128, 128, 128))
}

@Test(arguments: [0.3, 0.6, 0.9, 1])
func aJPEGRoundTripsCloseToItsPixels(quality: Double) throws {
    let codec = PNGJPEGCodec()
    let bitmap = try gradient(width: 64, height: 48, opaque: true)
    let data = try #require(codec.encode(bitmap, as: .jpeg, quality: quality, metadata: ImageMetadata()))
    let decoded = try #require(codec.decode(data))
    #expect(close(decoded, bitmap, within: quality < 0.5 ? 24 : 12))
}

@Test func aLowerJPEGQualityGivesASmallerFile() throws {
    let codec = PNGJPEGCodec()
    let bitmap = try gradient(width: 64, height: 64, opaque: true)
    let high = try #require(codec.encode(bitmap, as: .jpeg, quality: 0.95, metadata: ImageMetadata()))
    let low = try #require(codec.encode(bitmap, as: .jpeg, quality: 0.2, metadata: ImageMetadata()))
    #expect(low.count < high.count)
}

@Test(arguments: ImageFormat.allCases)
func whatABitmapIsEncodedWithReadsBackFromTheFile(format: ImageFormat) throws {
    let codec = PNGJPEGCodec()
    let bitmap = try gradient(width: 20, height: 10, scale: 2)
    let data = try #require(codec.encode(bitmap, as: format, quality: 0.9, metadata: ImageMetadata(windowShadow: true, record: record, projectID: "ID-1")))
    let url = temporaryFile(format)
    defer { try? FileManager.default.removeItem(at: url) }
    try data.write(to: url)
    #expect(codec.info(ofFileAt: url) == ImageFileInfo(isGIF: false, frames: 1, size: CaptureRecord.Size(width: 20, height: 10)))
    #expect(codec.info(of: data) == codec.info(ofFileAt: url))
    #expect(codec.scale(ofFileAt: url) == 2)
    #expect(codec.record(ofFileAt: url) == record)
    #expect(codec.projectID(ofFileAt: url) == "ID-1")
    #expect(codec.hasWindowShadow(ofFileAt: url))
    let read = try #require(codec.decode(fileAt: url))
    #expect(read.width == 20 && read.height == 10 && read.scale == 2)
}

@Test(arguments: ImageFormat.allCases)
func aFileWithoutMetadataHasNone(format: ImageFormat) throws {
    let codec = PNGJPEGCodec()
    let data = try #require(codec.encode(gradient(width: 4, height: 4), as: format, quality: 0.9, metadata: ImageMetadata()))
    let url = temporaryFile(format)
    defer { try? FileManager.default.removeItem(at: url) }
    try data.write(to: url)
    #expect(codec.scale(ofFileAt: url) == 1)
    #expect(codec.record(ofFileAt: url) == nil && codec.projectID(ofFileAt: url) == nil && !codec.hasWindowShadow(ofFileAt: url))
}

@Test func theMacsPNGDecodesWithItsPixelsAndMetadata() throws {
    let codec = PNGJPEGCodec()
    let url = fixture("mac-shot.png")
    let bitmap = try #require(codec.decode(fileAt: url))
    #expect(bitmap.width == 8 && bitmap.height == 6 && bitmap.scale == 2)
    for y in 0 ..< 6 {
        for x in 0 ..< 8 {
            let color = gradientColor(x: x, y: y), pixel = bitmap[x, y]
            let expected = [color.r * color.a, color.g * color.a, color.b * color.a, color.a].map { Int(($0 * 255).rounded()) }
            #expect(zip([pixel.r, pixel.g, pixel.b, pixel.a].map(Int.init), expected).allSatisfy { abs($0 - $1) <= 1 }, "\(x), \(y)")
        }
    }
    #expect(codec.scale(ofFileAt: url) == 2)
    #expect(codec.record(ofFileAt: url) == record)
    #expect(codec.projectID(ofFileAt: url) == projectID)
    #expect(codec.hasWindowShadow(ofFileAt: url))
    #expect(codec.scale(ofFileAt: fixture("mac-plain.png")) == 2)
    #expect(codec.record(ofFileAt: fixture("mac-plain.png")) == nil)
}

@Test func theMacsJPEGDecodesWithItsMetadata() throws {
    let codec = PNGJPEGCodec()
    let url = fixture("mac-shot.jpg")
    let bitmap = try #require(codec.decode(fileAt: url))
    #expect(bitmap.width == 8 && bitmap.height == 6 && bitmap.scale == 2)
    #expect(!BitmapImage(bitmap).hasTransparentPixels)
    #expect(codec.record(ofFileAt: url) == record)
    #expect(codec.projectID(ofFileAt: url) == projectID)
    #expect(codec.hasWindowShadow(ofFileAt: url))
    #expect(codec.record(ofFileAt: fixture("mac-big.jpg")) == bigRecord)
}

@Test(arguments: ["linux-shot.png", "linux-shot.jpg"])
func theFilesThisCodecWroteForTheMacStillReadTheSame(name: String) throws {
    let codec = PNGJPEGCodec()
    let url = fixture(name)
    #expect(codec.scale(ofFileAt: url) == 2)
    #expect(codec.record(ofFileAt: url) == record)
    #expect(codec.projectID(ofFileAt: url) == projectID)
    #expect(codec.hasWindowShadow(ofFileAt: url))
    #expect(codec.record(ofFileAt: fixture("linux-big.jpg")) == bigRecord)
}

@Test func aPreviewIsASmallOpaqueJPEGAndNeverBigger() throws {
    let codec = PNGJPEGCodec()
    let bitmap = try gradient(width: 300, height: 200)
    let preview = try #require(codec.previewJPEG(of: BitmapImage(bitmap), maxPixelSize: 150, maxBytes: 1_000_000))
    let decoded = try #require(codec.decode(preview))
    #expect(decoded.width == 150 && decoded.height == 100)
    #expect(!BitmapImage(decoded).hasTransparentPixels)
    let small = try #require(codec.previewJPEG(of: BitmapImage(bitmap), maxPixelSize: 1568, maxBytes: 1_000_000))
    #expect(codec.decode(small).map { ($0.width, $0.height) } ?? (0, 0) == (300, 200))
    let tight = try #require(codec.previewJPEG(of: BitmapImage(bitmap), maxPixelSize: 300, maxBytes: 2_000))
    #expect(tight.count <= 2_000)
    #expect(codec.previewJPEG(at: fixture("mac-shot.png")) != nil)
}

@Test func whatIsntAPNGOrJPEGDoesntDecode() {
    let codec = PNGJPEGCodec()
    let gif = Data("GIF89a".utf8) + Data(repeating: 0, count: 32)
    #expect(codec.decode(gif) == nil && codec.info(of: gif) == nil)
    #expect(codec.decode(Data("not an image".utf8)) == nil)
    #expect(codec.decode(fileAt: fixture("missing.png")) == nil)
    #expect(codec.scale(ofFileAt: fixture("missing.png")) == 1)
}

@Test func aPlacedImageRoundTripsThroughAProjectsPNG() throws {
    let codec = PNGJPEGCodec()
    let image = BitmapImage(try gradient(width: 5, height: 3))
    let png = try #require(codec.png(from: image))
    #expect(codec.image(fromPNG: png)?.bitmap == image.bitmap)
}
