import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import ShotCore

// The saved-file fixtures in Tests/Fixtures, read without ImageIO. SavedProjectTests reads the same files through
// ImageIOCodec and checks the placed image's pixels.

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)"))
}

/// Reads only a PNG's size, from its IHDR chunk, and makes a clear image that size. Writing an image gives back the PNG
/// it was read from, so a decoded file encodes to the same bytes.
private final class SizeOnlyPNG: PNGCoding {
    private let read = Mutex<[ObjectIdentifier: Data]>([:])

    func image(fromPNG data: Data) -> PlatformImage? {
        // The 8-byte signature, then IHDR's length and type, then its big-endian width and height.
        let bytes = [UInt8](data)
        guard bytes.count >= 24, bytes[12..<16].elementsEqual("IHDR".utf8) else {
            return nil
        }
        func number(at i: Int) -> Int { bytes[i..<i + 4].reduce(0) { $0 << 8 | Int($1) } }
        guard let image = Self.clearImage(width: number(at: 16), height: number(at: 20)) else {
            return nil
        }
        read.withLock { $0[ObjectIdentifier(image)] = data }
        return image
    }

    func png(from image: PlatformImage) -> Data? {
        read.withLock { $0[ObjectIdentifier(image)] }
    }

    private static func clearImage(width: Int, height: Int) -> PlatformImage? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
}

private let arrowID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let imageID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

/// The placed image's size and place, as the fixtures hold them.
private func expectFixturePicture(_ annotation: Annotation?) throws {
    guard case let .image(placed, rect) = try #require(annotation).kind else {
        Issue.record("not an image")
        return
    }
    #expect(placed.id == UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
    #expect(rect == CGRect(x: 5, y: 6, width: 12, height: 8))
    #expect(placed.image.width == 3 && placed.image.height == 2)
}

@Test func aSavedProjectReadsBackAndSavesTheSameBytesWithoutImageIO() throws {
    let saved = try fixture("project.json")
    let codec = SizeOnlyPNG()
    let project = try ProjectEntry.decoder(codec: codec).decode(StoredProject<EditorSnapshot>.self, from: saved)
    let layers = try #require(project.document)
    #expect(layers.annotations.count == 3)
    #expect(layers.annotations.first { $0.id == arrowID }?.bend == CGVector(dx: 1.5, dy: -6))
    try expectFixturePicture(layers.annotations.first { $0.id == imageID })
    #expect(try ProjectEntry.encoder(codec: codec).encode(project) == saved)
}

@Test func aLegacyRoundedRectangleReadsAsARectangleWithoutImageIO() throws {
    let codec = SizeOnlyPNG()
    let project = try ProjectEntry.decoder(codec: codec).decode(StoredProject<EditorSnapshot>.self, from: fixture("project-legacy.json"))
    let shape = try #require(project.document?.annotations.last)
    #expect(shape.kind == .shape(.rectangle, rect: CGRect(x: 4, y: 4, width: 20, height: 10)))
    #expect(shape.cornerRadius == 2)
    #expect(try ProjectEntry.encoder(codec: codec).encode(project) == fixture("project.json"))
}

@Test func aCopiedAnnotationPastesAndCopiesTheSameWithoutImageIO() throws {
    let copied = try fixture("annotation.json")
    let codec = SizeOnlyPNG()
    let annotation = try AnnotationClipboard.annotation(from: copied, codec: codec)
    try expectFixturePicture(annotation)
    // The pasteboard's JSON doesn't sort its keys, so the order changes from run to run; what it says doesn't.
    let again = try AnnotationClipboard.data(for: annotation, codec: codec)
    #expect(try JSONSerialization.jsonObject(with: again) as? NSDictionary == JSONSerialization.jsonObject(with: copied) as? NSDictionary)
}
