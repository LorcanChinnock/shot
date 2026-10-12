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

/// Long enough after now that pruning's grace for new entries is over.
private let later = Date().addingTimeInterval(ProjectPruning.grace + 60)

@Test(arguments: [ImageFormat.png, .jpeg])
func theProjectIDGoesInTheImagesXMPBesideTheRecord(format: ImageFormat) throws {
    let record = CaptureRecord(kind: "image", created: Date(timeIntervalSince1970: 1_791_640_992), size: .init(width: 20, height: 10), scale: 1)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("project-\(UUID().uuidString).\(format.fileExtension)")
    defer { try? FileManager.default.removeItem(at: url) }
    try #require(ImageCodec.data(from: solidImage(width: 20, height: 10), scale: 1, format: format, record: record, projectID: "ID-1")).write(to: url)
    #expect(ImageCodec.projectID(ofFileAt: url) == "ID-1")
    #expect(ImageCodec.record(ofFileAt: url) == record)

    try #require(ImageCodec.data(from: solidImage(width: 20, height: 10), scale: 1, format: format, projectID: "ID-2")).write(to: url)
    #expect(ImageCodec.projectID(ofFileAt: url) == "ID-2")
    #expect(ImageCodec.record(ofFileAt: url) == nil)
}

@Test func eachAppKeepsItsOwnStore() {
    #expect(ProjectStore(bundleID: "dev.lorcan.Shot.dev").folder.path.hasSuffix("Application Support/dev.lorcan.Shot.dev/Projects"))
}

@Test func aVersionsLayersComeBackAfterItAndItsOriginalMove() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let original = folder.appendingPathComponent("Shot.png"), version = folder.appendingPathComponent("Shot (2).png")
    try writePNG(to: original, id: nil)
    let id = ProjectKey.newID()
    try writePNG(to: version, id: id)
    let origin = ProjectOrigin(via: .mcp, client: "claude-code", action: "annotate")
    try store.save(Layers(marks: ["arrow", "blur"]), for: version, id: id, original: original, origin: origin)

    let moved = folder.appendingPathComponent("Moved", isDirectory: true)
    try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: original, to: moved.appendingPathComponent("Shot.png"))
    try FileManager.default.moveItem(at: version, to: moved.appendingPathComponent("Renamed.png"))

    let project = try #require(await store.project(for: moved.appendingPathComponent("Renamed.png"), as: Layers.self))
    #expect(project.document == Layers(marks: ["arrow", "blur"]))
    #expect(project.entry.origin == origin)
    #expect(project.entry.original?.locate()?.resolvingSymlinksInPath() == moved.appendingPathComponent("Shot.png").resolvingSymlinksInPath())
}

@Test func aCaptureWithNoLayersKeepsOnlyItsOrigin() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let capture = folder.appendingPathComponent("Shot.png"), id = ProjectKey.newID()
    try writePNG(to: capture, id: id)
    try store.save(origin: ProjectOrigin(via: .cli, action: "capture"), for: capture, id: id)

    let entry = try #require(await store.entry(for: capture))
    #expect(entry.origin.via == .cli)
    #expect(entry.origin.action == "capture")
    #expect(entry.original == nil)
    #expect(await store.project(for: capture, as: Layers.self)?.document == nil)
}

@Test func aFileWithNoStampOrOneTheStoreDoesntKnowHasNoProject() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let plain = folder.appendingPathComponent("Plain.png"), unknown = folder.appendingPathComponent("Unknown.png")
    try writePNG(to: plain, id: nil)
    try writePNG(to: unknown, id: ProjectKey.newID())
    #expect(await store.entry(for: plain) == nil)
    #expect(await store.entry(for: unknown) == nil)
    #expect(throws: ProjectStore.StoreError.noFile) {
        try store.save(origin: ProjectOrigin(via: .app), for: folder.appendingPathComponent("Missing.png"), id: "ID")
    }
}

@Test func aGIFIsFoundByItsInodeAfterARename() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let gif = folder.appendingPathComponent("Shot.gif")
    try Data("GIF89a".utf8).write(to: gif)
    let entry = try store.save(Layers(marks: ["trim"]), for: gif, id: nil, origin: ProjectOrigin(via: .app))
    #expect(!entry.stamped)
    #expect(ProjectKey.isIdentity(entry.id))

    let renamed = folder.appendingPathComponent("Renamed.gif")
    try FileManager.default.moveItem(at: gif, to: renamed)
    #expect(await store.project(for: renamed, as: Layers.self)?.document == Layers(marks: ["trim"]))
}

@Test func aGIFReplacedAtItsPathIsAnotherFileUntilItsSavedAgain() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let projects = folder.appendingPathComponent("Projects")
    let store = ProjectStore(folder: projects)
    let gif = folder.appendingPathComponent("Shot.gif")
    try Data("GIF89a one".utf8).write(to: gif)
    try store.save(Layers(marks: ["first"]), for: gif, id: nil, origin: ProjectOrigin(via: .app))

    try Data("GIF89a, another".utf8).write(to: gif, options: .atomic)
    #expect(await store.entry(for: gif) == nil)

    try store.save(Layers(marks: ["second"]), for: gif, id: nil, origin: ProjectOrigin(via: .cli, action: "gif"))
    #expect(await store.project(for: gif, as: Layers.self)?.document == Layers(marks: ["second"]))
    #expect(try FileManager.default.contentsOfDirectory(atPath: projects.path).count == 1)
}

@Test func pruningDropsProjectsWhoseFilesAreGoneOrReplaced() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let projects = folder.appendingPathComponent("Projects")
    let store = ProjectStore(folder: projects)
    let kept = folder.appendingPathComponent("Kept.png"), deleted = folder.appendingPathComponent("Deleted.png")
    let replaced = folder.appendingPathComponent("Replaced.png"), gif = folder.appendingPathComponent("Gone.gif")
    let keptID = ProjectKey.newID()
    for (url, id) in [(kept, keptID), (deleted, ProjectKey.newID()), (replaced, ProjectKey.newID())] {
        try writePNG(to: url, id: id)
        try store.save(origin: ProjectOrigin(via: .app), for: url, id: id)
    }
    try Data("GIF89a".utf8).write(to: gif)
    try store.save(origin: ProjectOrigin(via: .app), for: gif, id: nil)
    try FileManager.default.removeItem(at: deleted)
    try FileManager.default.removeItem(at: gif)
    try writePNG(to: replaced, id: nil)
    // An entry it can't read, perhaps from a newer Shot, stays.
    try Data("{}".utf8).write(to: projects.appendingPathComponent("\(ProjectKey.newID()).json"))

    #expect(await store.prune() == 0)
    #expect(await store.prune(now: later) == 3)
    #expect(await store.entry(for: kept)?.id == keptID)
    #expect(try FileManager.default.contentsOfDirectory(atPath: projects.path).count == 2)
}

@Test func pruningFollowsAFileThatMoved() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let capture = folder.appendingPathComponent("Shot.png"), id = ProjectKey.newID()
    try writePNG(to: capture, id: id)
    try store.save(origin: ProjectOrigin(via: .app), for: capture, id: id)
    try FileManager.default.moveItem(at: capture, to: folder.appendingPathComponent("Moved.png"))

    #expect(await store.prune(now: later) == 0)
}

extension MediaTests {
    @Test(arguments: ["mp4", "mov"])
    func aMoviesProjectIDIsStampedWithoutReencoding(_ fileExtension: String) async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appendingPathComponent("Recording.\(fileExtension)")
        try await writeSyntheticVideo(to: movie, seconds: 1, fps: 30, width: 320, height: 180)
        #expect(await ProjectStamp.id(ofFileAt: movie) == nil)

        let id = ProjectKey.newID()
        try await ProjectStamp.stamp(movieAt: movie, id: id)
        #expect(await ProjectStamp.id(ofFileAt: movie) == id)
        let track = try #require(await AVURLAsset(url: movie).loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 320, height: 180))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Recording.\(fileExtension)"])

        try await ProjectStamp.stamp(movieAt: movie, id: "ID-2")
        #expect(await ProjectStamp.id(ofFileAt: movie) == "ID-2")
    }

    @Test func aRecordingsVideoProjectRoundTrips() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
        let recording = folder.appendingPathComponent("Recording.mp4"), copy = folder.appendingPathComponent("Recording (2).mp4")
        try await writeSyntheticVideo(to: recording, seconds: 1, fps: 30, width: 320, height: 180)
        try FileManager.default.copyItem(at: recording, to: copy)
        let id = ProjectKey.newID()
        try await ProjectStamp.stamp(movieAt: copy, id: id)
        let project = Project(source: recording, duration: 1, canvasSize: CGSize(width: 320, height: 180), hasAudio: false)
        try store.save(project, for: copy, id: id, original: recording, origin: ProjectOrigin(via: .mcp, client: "cursor", action: "trim_video"))

        let stored = try #require(await store.project(for: copy, as: Project.self))
        #expect(stored.document == project)
        #expect(stored.entry.origin.client == "cursor")
        #expect(await store.entry(for: recording) == nil)
    }
}
