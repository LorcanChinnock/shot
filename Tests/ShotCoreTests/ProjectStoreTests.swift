import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

/// Stands in for an editor's layers, which the store keeps without knowing their shape.
private struct Layers: Codable, Equatable, Sendable {
    var marks: [String]
}

/// A PNG at `url` with `id` stamped in it.
private func writePNG(to url: URL, id: String?) throws {
    try #require(ImageCodec.data(from: solidImage(width: 20, height: 10), scale: 1, projectID: id)).write(to: url)
}

@Test(arguments: [ImageFormat.png, .jpeg])
func theProjectIDGoesInTheImagesXMP(format: ImageFormat) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("project-\(UUID().uuidString).\(format.fileExtension)")
    defer { try? FileManager.default.removeItem(at: url) }
    try #require(ImageCodec.data(from: solidImage(width: 20, height: 10), scale: 1, format: format, projectID: "ID-1")).write(to: url)
    #expect(ImageCodec.projectID(ofFileAt: url) == "ID-1")

    try #require(ImageCodec.data(from: solidImage(width: 20, height: 10), scale: 1, format: format, projectID: "ID-2")).write(to: url)
    #expect(ImageCodec.projectID(ofFileAt: url) == "ID-2")
}

@Test func eachAppKeepsItsOwnStore() {
    #expect(ProjectStore(bundleID: "dev.lorcan.Shot.dev").folder.path.hasSuffix("Application Support/dev.lorcan.Shot.dev/Projects"))
}

@Test func aVersionsLayersComeBackAfterItAndItsOriginalMove() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let original = folder.appendingPathComponent("Shot.png"), version = folder.appendingPathComponent("Shot (2).png")
    try writePNG(to: original, id: nil)
    let id = ProjectKey.newID()
    try writePNG(to: version, id: id)
    try store.save(Layers(marks: ["arrow", "blur"]), for: version, id: id, original: original)

    let moved = folder.appendingPathComponent("Moved", isDirectory: true)
    try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: original, to: moved.appendingPathComponent("Shot.png"))
    try FileManager.default.moveItem(at: version, to: moved.appendingPathComponent("Renamed.png"))

    let project = try #require(store.project(for: moved.appendingPathComponent("Renamed.png"), as: Layers.self))
    #expect(project.document == Layers(marks: ["arrow", "blur"]))
    #expect(project.entry.original?.locate()?.resolvingSymlinksInPath() == moved.appendingPathComponent("Shot.png").resolvingSymlinksInPath())
}

@Test func anEntryWithNoLayersKeepsOnlyTheFile() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let capture = folder.appendingPathComponent("Shot.png"), id = ProjectKey.newID()
    try writePNG(to: capture, id: id)
    try store.save(String?.none, for: capture, id: id)

    let entry = try #require(store.entry(for: capture))
    #expect(entry.original == nil)
    #expect(store.project(for: capture, as: Layers.self)?.document == nil)
}

@Test func aFileWithNoStampOrOneTheStoreDoesntKnowHasNoProject() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let plain = folder.appendingPathComponent("Plain.png"), unknown = folder.appendingPathComponent("Unknown.png")
    try writePNG(to: plain, id: nil)
    try writePNG(to: unknown, id: ProjectKey.newID())
    #expect(store.entry(for: plain) == nil)
    #expect(store.entry(for: unknown) == nil)
    #expect(throws: ProjectStore.StoreError.noFile) {
        try store.save(String?.none, for: folder.appendingPathComponent("Missing.png"), id: "ID")
    }
}

@Test func aGIFIsFoundByItsInodeAfterARename() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let gif = folder.appendingPathComponent("Shot.gif")
    try Data("GIF89a".utf8).write(to: gif)
    let entry = try store.save(Layers(marks: ["trim"]), for: gif, id: nil)
    #expect(!entry.stamped)
    #expect(ProjectKey.isIdentity(entry.id))

    let renamed = folder.appendingPathComponent("Renamed.gif")
    try FileManager.default.moveItem(at: gif, to: renamed)
    #expect(store.project(for: renamed, as: Layers.self)?.document == Layers(marks: ["trim"]))
}

@Test func aGIFReplacedAtItsPathIsAnotherFileUntilItsSavedAgain() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let projects = folder.appendingPathComponent("Projects")
    let store = ProjectStore(folder: projects)
    let gif = folder.appendingPathComponent("Shot.gif")
    try Data("GIF89a one".utf8).write(to: gif)
    try store.save(Layers(marks: ["first"]), for: gif, id: nil)

    try Data("GIF89a, another".utf8).write(to: gif, options: .atomic)
    #expect(store.entry(for: gif) == nil)

    try store.save(Layers(marks: ["second"]), for: gif, id: nil)
    #expect(store.project(for: gif, as: Layers.self)?.document == Layers(marks: ["second"]))
    #expect(try FileManager.default.contentsOfDirectory(atPath: projects.path).count == 1)
}

@Test func pruningDropsProjectsWhoseFilesAreGoneOrReplaced() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let projects = folder.appendingPathComponent("Projects")
    let store = ProjectStore(folder: projects)
    let kept = folder.appendingPathComponent("Kept.png"), deleted = folder.appendingPathComponent("Deleted.png")
    let replaced = folder.appendingPathComponent("Replaced.png"), gif = folder.appendingPathComponent("Gone.gif")
    let keptID = ProjectKey.newID()
    for (url, id) in [(kept, keptID), (deleted, ProjectKey.newID()), (replaced, ProjectKey.newID())] {
        try writePNG(to: url, id: id)
        try store.save(String?.none, for: url, id: id)
    }
    try Data("GIF89a".utf8).write(to: gif)
    try store.save(String?.none, for: gif, id: nil)
    try FileManager.default.removeItem(at: deleted)
    try FileManager.default.removeItem(at: gif)
    try writePNG(to: replaced, id: nil)
    // An entry it can't read, perhaps from a newer Shot, stays.
    try Data("{}".utf8).write(to: projects.appendingPathComponent("\(ProjectKey.newID()).json"))

    #expect(store.prune() == 3)
    #expect(store.entry(for: kept)?.id == keptID)
    #expect(try FileManager.default.contentsOfDirectory(atPath: projects.path).count == 2)
}

@Test func pruningFollowsAFileThatMoved() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let capture = folder.appendingPathComponent("Shot.png"), id = ProjectKey.newID()
    try writePNG(to: capture, id: id)
    try store.save(String?.none, for: capture, id: id)
    try FileManager.default.moveItem(at: capture, to: folder.appendingPathComponent("Moved.png"))

    #expect(store.prune() == 0)
}

@Test func anEntryAnOlderShotWroteWithAnOriginStillLoads() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let projects = folder.appendingPathComponent("Projects")
    let store = ProjectStore(folder: projects)
    let capture = folder.appendingPathComponent("Shot.png"), id = ProjectKey.newID()
    try writePNG(to: capture, id: id)
    try store.save(Layers(marks: ["arrow"]), for: capture, id: id)
    let name = try #require(ProjectKey.fileName(for: id))
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: projects.appendingPathComponent(name))) as? [String: Any])
    object["origin"] = ["via": "mcp", "client": "claude-code", "action": "annotate", "date": "2026-10-10T14:03:12Z"]
    try JSONSerialization.data(withJSONObject: object).write(to: projects.appendingPathComponent(name))

    let project = try #require(store.project(for: capture, as: Layers.self))
    #expect(project.document == Layers(marks: ["arrow"]))
    #expect(store.entry(for: capture)?.id == id)
}

extension MediaTests {
    @Test(arguments: ["mp4", "mov"])
    func aMoviesProjectIDIsStampedWithoutReencoding(_ fileExtension: String) async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Source.mp4"), movie = folder.appendingPathComponent("Recording.\(fileExtension)")
        try await writeSyntheticVideo(to: source, seconds: 1, fps: 30, width: 320, height: 180)
        // A real QuickTime movie for MOV, not an MP4 under another name.
        let export = try #require(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough))
        try await export.export(to: movie, as: fileExtension == "mov" ? .mov : .mp4)
        try FileManager.default.removeItem(at: source)
        #expect(ProjectStamp.id(ofFileAt: movie) == nil)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: movie.path)[.size] as? Int)

        let id = ProjectKey.newID()
        try ProjectStamp.stamp(movieAt: movie, id: id)
        #expect(ProjectStamp.id(ofFileAt: movie) == id)
        #expect(try FileManager.default.attributesOfItem(atPath: movie.path)[.size] as? Int == size + MovieStampBox.box(id: id).count)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Recording.\(fileExtension)"])
        // AVFoundation still reads the whole movie, frames included.
        let asset = AVURLAsset(url: movie)
        let track = try #require(await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 320, height: 180))
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.1)
        #expect(try await AVAssetImageGenerator(asset: asset).image(at: CMTime(value: 1, timescale: 2)).image.width == 320)

        try ProjectStamp.stamp(movieAt: movie, id: "ID-2")
        #expect(ProjectStamp.id(ofFileAt: movie) == "ID-2")
    }

    @Test func aMovieWhoseLastBoxRunsToTheEndIsntStamped() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appendingPathComponent("Open.mp4")
        // An ftyp box, then an mdat of size 0, which means "to the end of the file", so nothing may follow it.
        let ftyp: [UInt8] = [0, 0, 0, 16] + Array("ftypisom".utf8) + [0, 0, 2, 0]
        let mdat: [UInt8] = [0, 0, 0, 0] + Array("mdat".utf8) + [1, 2, 3, 4]
        try Data(ftyp + mdat).write(to: movie)
        #expect(throws: CocoaError.self) { try ProjectStamp.stamp(movieAt: movie, id: "ID") }
        #expect(try Data(contentsOf: movie) == Data(ftyp + mdat))
    }

    @Test func aRecordingsVideoProjectRoundTrips() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
        let recording = folder.appendingPathComponent("Recording.mp4"), copy = folder.appendingPathComponent("Recording (2).mp4")
        try await writeSyntheticVideo(to: recording, seconds: 1, fps: 30, width: 320, height: 180)
        try FileManager.default.copyItem(at: recording, to: copy)
        let id = ProjectKey.newID()
        try ProjectStamp.stamp(movieAt: copy, id: id)
        let project = Project(source: recording, duration: 1, canvasSize: CGSize(width: 320, height: 180), hasAudio: false)
        try store.save(project, for: copy, id: id, original: recording)

        let stored = try #require(store.project(for: copy, as: Project.self))
        #expect(stored.document == project)
        #expect(store.entry(for: recording) == nil)
    }
}
