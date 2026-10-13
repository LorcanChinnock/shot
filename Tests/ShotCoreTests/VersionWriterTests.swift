import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private func plainImage(width: Int = 120, height: Int = 80) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

private let arrow = Annotation(kind: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40)), color: RGBA.presets[0], lineWidth: 4)

@Test func aVersionSavedInAnotherFormatTakesThatFormatsExtension() {
    let folder = URL(fileURLWithPath: "/tmp/shots")
    let none: (URL) -> Bool = { _ in false }
    // Shot writes only PNG and JPEG, so a HEIC or TIFF saves as PNG and its version must say so.
    #expect(VersionWriter.nextVersionURL(of: folder.appendingPathComponent("Photo.heic"), savedAs: .png, exists: none).lastPathComponent == "Photo (2).png")
    #expect(VersionWriter.nextVersionURL(of: folder.appendingPathComponent("Scan (2).tiff"), savedAs: .png, exists: none).lastPathComponent == "Scan (2).png")
    // An extension that already names the format is kept as written.
    #expect(VersionWriter.nextVersionURL(of: folder.appendingPathComponent("Photo.jpeg"), savedAs: .jpeg, exists: none).lastPathComponent == "Photo (2).jpeg")
    #expect(VersionWriter.nextVersionURL(of: folder.appendingPathComponent("Photo.JPG"), savedAs: .jpeg, exists: none).lastPathComponent == "Photo (2).JPG")
    let taken: Set<String> = ["Photo (2).png"]
    #expect(VersionWriter.nextVersionURL(of: folder.appendingPathComponent("Photo.heic"), savedAs: .png) { taken.contains($0.lastPathComponent) }.lastPathComponent == "Photo (3).png")
}

@Test func savingAnImageWritesItsNextVersionAndRecordsMarksOnlyForAgents() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: plainImage(), scale: 2)).write(to: original)
    let document = EditorDocument(base: plainImage(), annotations: [arrow])

    let quiet = try VersionWriter.saveImage(document, of: original, scale: 2, recordForAgents: false)
    #expect(quiet.url.lastPathComponent == "Shot (2).png")
    #expect(try Data(contentsOf: quiet.url) == quiet.png)
    #expect(ImageCodec.record(ofFileAt: quiet.url) == nil)
    #expect(ImageCodec.scale(ofFileAt: quiet.url) == 2)

    let recorded = try VersionWriter.saveImage(document, of: original, scale: 2, recordForAgents: true)
    #expect(recorded.url.lastPathComponent == "Shot (3).png")
    let record = try #require(ImageCodec.record(ofFileAt: recorded.url))
    #expect(record.original == "Shot.png")
    #expect(record.size == CaptureRecord.Size(width: 120, height: 80))
    #expect(record.canvas == [0, 0, 120, 80])
    #expect(record.editable == true)
    #expect(record.annotations.map(\.type) == ["arrow"])
}

@Test func aJPEGVersionStaysJPEGAndStillGivesAPNGForTheClipboard() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("Shot.jpeg")
    try #require(ImageCodec.data(from: plainImage(), scale: 1, format: .jpeg)).write(to: original)
    let document = EditorDocument(base: plainImage(), annotations: [arrow], background: EditorDocument.defaultBackground(for: .jpeg))

    let saved = try VersionWriter.saveImage(document, of: original, scale: 1, recordForAgents: true)
    #expect(saved.url.lastPathComponent == "Shot (2).jpeg")
    #expect(ImageCodec.image(from: saved.png) != nil)
    #expect(try Data(contentsOf: saved.url) != saved.png)
    #expect(ImageCodec.record(ofFileAt: saved.url)?.editable == true)
}

@Test func aRecordIsntEditableOnceTheCaptureIsStyledOrItsBackgroundChanged() {
    let original = URL(fileURLWithPath: "/tmp/shots/Shot.png")
    var document = EditorDocument(base: plainImage(), annotations: [arrow])
    #expect(VersionWriter.record(of: document, drawnOn: original, savedAs: .png, scale: 1).editable == true)
    document.captureCornerRadius = 8
    #expect(VersionWriter.record(of: document, drawnOn: original, savedAs: .png, scale: 1).editable == false)
    document.captureCornerRadius = 0
    document.background = RGBA(1, 1, 1)
    #expect(VersionWriter.record(of: document, drawnOn: original, savedAs: .png, scale: 1).editable == false)
    // White is JPEG's own background, so there it's no change.
    #expect(VersionWriter.record(of: document, drawnOn: original, savedAs: .jpeg, scale: 1).editable == true)
}

@Test func aVideoCopyIsANewCaptureNameInTheRecordingsFormat() {
    let folder = URL(fileURLWithPath: "/tmp/shots-\(UUID().uuidString)")
    var components = DateComponents()
    components.year = 2026; components.month = 10; components.day = 2
    components.hour = 14; components.minute = 3; components.second = 11
    let date = Calendar.current.date(from: components)!
    #expect(VersionWriter.videoCopyURL(of: folder.appendingPathComponent("Clip.mov"), prefix: "Shot", date: date).lastPathComponent == "Shot 2026-10-02 at 14.03.11.mov")
    #expect(VersionWriter.videoCopyURL(of: folder.appendingPathComponent("Clip.m4v"), prefix: "Bug", date: date).lastPathComponent == "Bug 2026-10-02 at 14.03.11.mp4")
}

@Test func aSavedVersionsLayersComeBackLiveWithoutTheAgentSetting() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let original = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: plainImage(), scale: 2)).write(to: original)
    // Everything a record can't hold: a placed image, a spotlight, a hidden and a styled layer, a styled screenshot.
    var document = EditorDocument(base: plainImage(), annotations: [arrow])
    document.addImage(plainImage(width: 20, height: 20), scale: 2, documentScale: 2, centeredAt: CGPoint(x: 30, y: 30), margin: 16)
    document.annotations.append(Annotation(kind: .spotlight(CGRect(x: 5, y: 5, width: 40, height: 30), style: SpotlightStyle()), color: RGBA(0, 0, 0), lineWidth: 0))
    document.annotations[0].isHidden = true
    document.annotations[1].style = ObjectStyle(shadow: Shadow(elevation: 8, opacity: 0.3))
    document.setCornerRadius(12, of: .capture)
    document.background = RGBA(0.2, 0.4, 0.6)

    let saved = try VersionWriter.saveImage(document, of: original, scale: 2, recordForAgents: false, projects: store)
    #expect(ImageCodec.record(ofFileAt: saved.url) == nil)
    let reopened = try #require(VersionWriter.layers(of: saved.url, in: store))
    #expect(reopened.original.resolvingSymlinksInPath() == original.resolvingSymlinksInPath())
    #expect(reopened.layers == document.snapshot)
    #expect(store.entry(for: saved.url)?.origin.via == .app)
}

@Test func aVersionOpensFlatWhenItsOriginalIsReplacedButFollowsItWhenMoved() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let original = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: plainImage(), scale: 1)).write(to: original)
    let saved = try VersionWriter.saveImage(EditorDocument(base: plainImage(), annotations: [arrow]), of: original, scale: 1, recordForAgents: false, projects: store)

    let moved = folder.appendingPathComponent("Moved.png")
    try FileManager.default.moveItem(at: original, to: moved)
    #expect(VersionWriter.layers(of: saved.url, in: store)?.original.resolvingSymlinksInPath() == moved.resolvingSymlinksInPath())

    // Another image put where the original was, and the original gone, isn't what the layers were drawn on.
    try FileManager.default.removeItem(at: moved)
    // JPEG bytes, so it can't be the same size as the original, which with the same path and second would pass for it.
    try #require(ImageCodec.data(from: plainImage(width: 200, height: 50), scale: 1, format: .jpeg)).write(to: original)
    #expect(VersionWriter.layers(of: saved.url, in: store) == nil)
}

@Test func aVersionSavedWithoutAStoreHasNoProject() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: plainImage(), scale: 1)).write(to: original)
    let saved = try VersionWriter.saveImage(EditorDocument(base: plainImage(), annotations: [arrow]), of: original, scale: 1, recordForAgents: false)
    #expect(ImageCodec.projectID(ofFileAt: saved.url) == nil)
}
