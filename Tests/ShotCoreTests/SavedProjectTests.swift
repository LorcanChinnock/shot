import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

// Projects and copied annotations as an earlier Shot saved them, so a change to how they're coded can't break old
// files. The files in Tests/Fixtures were written by main at e089aa5: `project.json` by `ProjectStore`,
// `project-legacy.json` is the same project with its rectangle saved as an older version saved a rounded one, and
// `annotation.json` by `AnnotationClipboard`. Each holds a bent arrow and a 3×2 placed image with a clear and a
// half-clear pixel.

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)"))
}

private let arrowID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
private let imageID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

/// The placed image's pixels, as the fixtures hold them.
private func expectFixturePicture(_ annotation: Annotation?) throws {
    guard case let .image(placed, rect) = try #require(annotation).kind else {
        Issue.record("not an image")
        return
    }
    #expect(placed.id == UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
    #expect(rect == CGRect(x: 5, y: 6, width: 12, height: 8))
    let bitmap = try #require(Bitmap(placed.image))
    #expect(bitmap.width == 3 && bitmap.height == 2)
    #expect(bitmap[0, 1].a == 0)
    #expect(bitmap[2, 0].a == 128)
    #expect(bitmap[1, 0].a == 255)
    #expect(placed.hasTransparency)
}

@Test func anEarlierSavedProjectReadsBackAndSavesTheSameBytes() throws {
    let saved = try fixture("project.json")
    let project = try ProjectEntry.decoder().decode(StoredProject<EditorSnapshot>.self, from: saved)
    let layers = try #require(project.document)
    #expect(layers.annotations.count == 3)
    #expect(layers.annotations.first { $0.id == arrowID }?.bend == CGVector(dx: 1.5, dy: -6))
    try expectFixturePicture(layers.annotations.first { $0.id == imageID })
    #expect(try ProjectEntry.encoder().encode(project) == saved)
}

@Test func aLegacyRoundedRectangleInASavedProjectSavesAsMainSavedIt() throws {
    let project = try ProjectEntry.decoder().decode(StoredProject<EditorSnapshot>.self, from: fixture("project-legacy.json"))
    let shape = try #require(project.document?.annotations.last)
    #expect(shape.kind == .shape(.rectangle, rect: CGRect(x: 4, y: 4, width: 20, height: 10)))
    #expect(shape.cornerRadius == 2)
    #expect(try ProjectEntry.encoder().encode(project) == fixture("project.json"))
}

@Test func anEarlierCopiedAnnotationPastesAndCopiesTheSame() throws {
    let copied = try fixture("annotation.json")
    let annotation = try AnnotationClipboard.annotation(from: copied)
    try expectFixturePicture(annotation)
    // The pasteboard's JSON doesn't sort its keys, so the order changes from run to run; what it says doesn't.
    let again = try AnnotationClipboard.data(for: annotation)
    #expect(try JSONSerialization.jsonObject(with: again) as? NSDictionary == JSONSerialization.jsonObject(with: copied) as? NSDictionary)
}

@Test func aPlacedImageEncodesAndDecodesWithAPlainJSONCoder() throws {
    let picture = try JSONDecoder().decode(Annotation.self, from: fixture("annotation.json"))
    try expectFixturePicture(picture)
    #expect(try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(picture)) == picture)
}

@Test func aPlacedImagesPixelsSurviveTheProjectStore() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: solidImage(width: 20, height: 10), scale: 1, projectID: "ID-1")).write(to: file)
    let picture = try #require(try ProjectEntry.decoder().decode(StoredProject<EditorSnapshot>.self, from: fixture("project.json")).document)

    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    try store.save(picture, for: file, id: "ID-1", origin: ProjectOrigin(via: .app))
    let layers = try #require(store.project(for: file, as: EditorSnapshot.self)?.document)
    #expect(layers == picture)
    try expectFixturePicture(layers.annotations.first { $0.id == imageID })
}

@Test func aPlacedImagesPixelsSurviveTheClipboard() throws {
    let picture = try AnnotationClipboard.annotation(from: fixture("annotation.json"))
    let pasted = try AnnotationClipboard.annotation(from: AnnotationClipboard.data(for: picture))
    #expect(pasted == picture)
    try expectFixturePicture(pasted)
}

/// Which pixels of an 80×60 image aren't opaque.
private enum Clearing: String, CaseIterable {
    case none, corner, edgeRow, faintPixel, allHalfClear

    /// Each as x, y and alpha.
    var pixels: [(x: Int, y: Int, alpha: UInt8)] {
        switch self {
        case .none: []
        case .corner: [(0, 0, 0)]
        case .edgeRow: (0..<80).map { ($0, 59, 0) }
        case .faintPixel: [(40, 30, 200)]
        case .allHalfClear: (0..<80).flatMap { x in (0..<60).map { y in (x, y, 128) } }
        }
    }
}

@Test(arguments: Clearing.allCases)
private func anImageSaysWhetherAnyPixelIsSeeThrough(clearing: Clearing) throws {
    var pixels = Data(repeating: 255, count: 80 * 60 * 4)
    for (x, y, alpha) in clearing.pixels {
        let i = (y * 80 + x) * 4
        pixels.replaceSubrange(i..<i + 4, with: [alpha, alpha, alpha, alpha])
    }
    let bitmap = try #require(Bitmap(width: 80, height: 60, pixels: pixels))
    let image = try #require(bitmap.cgImage)
    #expect(image.hasTransparentPixels == (clearing != .none))
}
