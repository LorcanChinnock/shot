import Foundation
import Testing
@testable import ShotModel

// The image fixtures in Tests/Fixtures were written by ImageIOCodec on macOS: `mac-shot.png` and `mac-shot.jpg` at
// scale 2 with every piece of metadata, `mac-plain.png` with none, and `mac-big.jpg` with a record too big for one JPEG
// segment, which ImageIO splits into extended XMP.

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)"))
}

let macRecord = CaptureRecord(
    original: "Shot 2026-10-20 at 10.00.00.png", kind: "image", created: Date(timeIntervalSince1970: 1_791_640_992), size: .init(width: 4, height: 3), scale: 2,
    source: .init(mode: "window", app: "Notes"), annotations: [CaptureMark(type: "counter", center: [2, 1], text: "Café ✓", number: 1)]
)
let macProjectID = "6F9619FF-8B86-D011-B42D-00CF4FC964FF"
let macBigRecord = CaptureRecord(
    kind: "image", created: Date(timeIntervalSince1970: 1_791_640_992), size: .init(width: 8, height: 6), scale: 1,
    annotations: [CaptureMark(type: "text", text: String(repeating: "Shot ", count: 14_000))]
)

/// A PNG of only its header, as libpng starts one, which is all `ImageHeader` reads.
private func bareImage(_ format: ImageFormat, width: Int = 30, height: Int = 20) -> Data {
    let size = Data.bigEndian(width, size: format == .png ? 4 : 2), tall = Data.bigEndian(height, size: format == .png ? 4 : 2)
    if format == .png {
        return PNGChunks.signature + PNGChunks.chunk("IHDR", size + tall + [8, 6, 0, 0, 0]) + PNGChunks.chunk("IEND", Data())
    }
    // SOI, the JFIF segment libjpeg writes, a baseline frame of three components, and the start of the scan.
    let jfif = Data([0xFF, 0xE0, 0, 16]) + Data("JFIF\0".utf8) + [1, 1, 0, 0, 1, 0, 1, 0, 0]
    let frame = Data([0xFF, 0xC0, 0, 17, 8]) + tall + size + [3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]
    return Data([0xFF, 0xD8]) + jfif + frame + [0xFF, 0xDA, 0, 2, 0xFF, 0xD9]
}

@Test func theMacsPNGSaysItsSizeScaleAndMetadata() throws {
    let header = try #require(ImageHeader(fixture("mac-shot.png")))
    #expect(header.format == .png && header.width == 8 && header.height == 6)
    #expect(header.dpi == 144 && header.scale == 2)
    #expect(header.metadata == ImageMetadata(windowShadow: true, record: macRecord, projectID: macProjectID))
}

@Test func theMacsJPEGSaysItsSizeScaleAndMetadata() throws {
    let header = try #require(ImageHeader(fixture("mac-shot.jpg")))
    #expect(header.format == .jpeg && header.width == 8 && header.height == 6)
    #expect(header.dpi == 144 && header.scale == 2)
    #expect(header.metadata == ImageMetadata(windowShadow: true, record: macRecord, projectID: macProjectID))
}

@Test func aPNGWithoutMetadataHasNone() throws {
    let header = try #require(ImageHeader(fixture("mac-plain.png")))
    #expect(header.scale == 2)
    #expect(header.metadata == ImageMetadata())
}

@Test func aRecordTheMacSplitIntoExtendedXMPReadsWhole() throws {
    let header = try #require(ImageHeader(fixture("mac-big.jpg")))
    #expect(header.metadata == ImageMetadata(record: macBigRecord, projectID: macProjectID))
}

@Test(arguments: ImageFormat.allCases, [false, true])
func whatsAddedToAnImageReadsBack(format: ImageFormat, everything: Bool) throws {
    let metadata = everything ? ImageMetadata(windowShadow: true, record: macRecord, projectID: macProjectID) : ImageMetadata()
    let data = try #require(ImageHeader.adding(dpi: 108, metadata: metadata, to: bareImage(format)))
    let header = try #require(ImageHeader(data))
    #expect(header == ImageHeader(format: format, width: 30, height: 20, dpi: 108, metadata: metadata))
    #expect(header.scale == 1.5)
}

@Test func aRecordTooBigForOneJPEGSegmentGoesInExtendedXMP() throws {
    let metadata = ImageMetadata(record: macBigRecord, projectID: macProjectID)
    let data = try #require(ImageHeader.adding(dpi: 72, metadata: metadata, to: bareImage(.jpeg)))
    let segments = try #require(JPEGSegments.segments(of: data))
    #expect(segments.filter { $0.payload.starts(with: JPEGSegments.extendedXMP) }.count == 2)
    #expect(segments.allSatisfy { $0.payload.count <= JPEGSegments.maxPayload })
    #expect(ImageHeader(data)?.metadata == metadata)
}

@Test func addingReplacesTheJFIFSegmentLibjpegWrote() throws {
    let data = try #require(ImageHeader.adding(dpi: 144, metadata: ImageMetadata(), to: bareImage(.jpeg)))
    let segments = try #require(JPEGSegments.segments(of: data))
    #expect(segments.map(\.marker) == [JPEGSegments.app0, 0xC0])
}

@Test func onlyPNGAndJPEGHaveAHeader() {
    #expect(ImageHeader(Data("GIF89a".utf8)) == nil)
    #expect(ImageHeader(Data("not an image".utf8)) == nil)
    #expect(ImageHeader(Data()) == nil)
    #expect(ImageHeader.adding(dpi: 72, metadata: ImageMetadata(), to: Data("GIF89a".utf8)) == nil)
}

@Test func aTruncatedImageStillSaysWhatItHolds() throws {
    let data = try fixture("mac-shot.png")
    let header = try #require(ImageHeader(data.prefix(data.count - 20)))
    #expect(header.metadata.projectID == macProjectID)
    #expect(ImageHeader(data.prefix(20)) == nil)
}

@Test func thePNGChecksumIsZlibs() {
    #expect(PNGChunks.crc32(Data("IEND".utf8)) == 0xAE42_6082)
}

@Test func aLittleEndianExifCommentReads() throws {
    // II, 42, the first directory at 8 pointing to the Exif directory at 26, and that to the comment at 44.
    func little(_ value: Int, _ size: Int) -> Data { Data(Data.bigEndian(value, size: size).reversed()) }
    func entry(_ tag: Int, _ type: Int, _ count: Int, _ value: Int) -> Data { little(tag, 2) + little(type, 2) + little(count, 4) + little(value, 4) }
    let comment = Data("ASCII\0\0\0Hello  ".utf8)
    let tiff = Data("II".utf8) + little(42, 2) + little(8, 4) + little(1, 2) + entry(0x8769, 4, 1, 26) + little(0, 4)
        + little(1, 2) + entry(0x9286, 7, comment.count, 44) + little(0, 4) + comment
    #expect(Exif(tiff: tiff)?.userComment == "Hello")
    #expect(Exif(tiff: tiff)?.dpi == nil)
    #expect(Exif(tiff: Exif.tiff(userComment: "Café"))?.userComment == "Café")
    #expect(Exif(tiff: Data("not a tiff".utf8)) == nil)
}

@Test func anXMPPropertyReadsAsAnAttributeOrAnElementWhateverItsPrefix() {
    let ns = ImageMetadata.xmpNamespace
    #expect(XMP.property("record", namespace: ns, in: "<d xmlns:s=\"\(ns)\" s:record=\"a &amp; &quot;b&quot; &#x2713;\"/>") == "a & \"b\" ✓")
    #expect(XMP.property("record", namespace: ns, in: "<d xmlns:s='\(ns)'><s:record>x &lt; y</s:record></d>") == "x < y")
    #expect(XMP.property("record", namespace: ns, in: "<d xmlns:s=\"\(ns)\"><s:recordings>no</s:recordings></d>") == nil)
    #expect(XMP.property("record", namespace: ns, in: "<d xmlns:s=\"other\" s:record=\"no\"/>") == nil)
    #expect(XMP.property("record", namespace: ns, in: "<d xmlns:s=\"\(ns)\"><s:record/></d>") == "")
    #expect(XMP.unescaped("a & b &bogus; &#65;") == "a & b &bogus; A")
}

@Test func aBitmapScalesDownToTheAverageOfEachBlockAndNeverUp() throws {
    // 4×2: two white opaque pixels then two clear ones, on each row.
    let row: [UInt8] = [255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0]
    let bitmap = try #require(Bitmap(width: 4, height: 2, scale: 2, pixels: Data(row + row)))
    #expect(bitmap.scaledDown(toFit: 8) == bitmap)
    let half = bitmap.scaledDown(toFit: 2)
    #expect(half.width == 2 && half.height == 1 && half.scale == 2)
    #expect(half[0, 0] == (255, 255, 255, 255) && half[1, 0] == (0, 0, 0, 0))
    let averaged = bitmap.scaledDown(toFit: 1)
    #expect(averaged.width == 1 && averaged.height == 1)
    #expect(averaged[0, 0] == (128, 128, 128, 128))
}

@Test func aBitmapOverWhiteIsOpaque() throws {
    // Clear, then half-transparent premultiplied red.
    let bitmap = try #require(Bitmap(width: 2, height: 1, pixels: Data([0, 0, 0, 0, 128, 0, 0, 128])))
    let opaque = bitmap.overWhite
    #expect(opaque[0, 0] == (255, 255, 255, 255))
    #expect(opaque[1, 0] == (255, 127, 127, 255))
}
