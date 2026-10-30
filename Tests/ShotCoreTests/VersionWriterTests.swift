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

@Test func savingAnImageWritesItsNextVersionAndKeepsItsScale() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: plainImage(), scale: 2)).write(to: original)
    let document = EditorDocument(base: plainImage(), annotations: [arrow])

    let saved = try VersionWriter.saveImage(document, of: original, scale: 2)
    #expect(saved.url.lastPathComponent == "Shot (2).png")
    #expect(try Data(contentsOf: saved.url) == saved.png)
    #expect(ImageCodec.scale(ofFileAt: saved.url) == 2)

    let next = try VersionWriter.saveImage(document, of: original, scale: 2)
    #expect(next.url.lastPathComponent == "Shot (3).png")
}

@Test func savingOverAnImageKeepsItsPristineCopyForTheLayersToSitOn() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("Shot.png")
    let pristineBytes = try #require(ImageCodec.data(from: plainImage(), scale: 2))
    try pristineBytes.write(to: original)
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let document = EditorDocument(base: plainImage(), annotations: [arrow])

    let saved = try VersionWriter.saveImage(document, of: original, overwriting: true, scale: 2, projects: store)
    #expect(saved.url == original)
    #expect(try Data(contentsOf: original) == saved.png)
    #expect(try Data(contentsOf: saved.original) == pristineBytes)
    #expect(store.keeps(saved.original))
    let reopened = try #require(VersionWriter.savedLayers(of: original, in: store))
    #expect(reopened.original.resolvingSymlinksInPath() == saved.original.resolvingSymlinksInPath())

    let again = try VersionWriter.saveImage(document, of: original, pristine: saved.original, overwriting: true, scale: 2, projects: store)
    #expect(again.original == saved.original)
    #expect(try Data(contentsOf: again.original) == pristineBytes)
    #expect(try FileManager.default.contentsOfDirectory(atPath: store.originalsFolder.path).count == 1)
}

@Test func aFileChangedOutsideShotOpensFlatAndRevertingPutsTheOriginalBack() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("Shot.png")
    let pristineBytes = try #require(ImageCodec.data(from: plainImage(), scale: 1))
    try pristineBytes.write(to: original)
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let saved = try VersionWriter.saveImage(EditorDocument(base: plainImage(), annotations: [arrow]), of: original, overwriting: true, scale: 1, projects: store)
    #expect(VersionWriter.savedLayers(of: original, in: store) != nil)

    try VersionWriter.revert(original, to: saved.original)
    #expect(try Data(contentsOf: original) == pristineBytes)
    #expect(VersionWriter.savedLayers(of: original, in: store) == nil)

    try Data("changed".utf8).write(to: original)
    #expect(VersionWriter.savedLayers(of: original, in: store) == nil)
}

@Test func keptOriginalsCanBeCountedAndDeleted() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: plainImage(), scale: 1)).write(to: original)
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    #expect(store.keptOriginalsSize() == 0)
    let saved = try VersionWriter.saveImage(EditorDocument(base: plainImage(), annotations: [arrow]), of: original, overwriting: true, scale: 1, projects: store)
    #expect(store.keptOriginalsSize() > 0)
    store.removeKeptOriginals()
    #expect(!FileManager.default.fileExists(atPath: saved.original.path))
    #expect(VersionWriter.savedLayers(of: original, in: store) == nil)
}

@Test func savingOverNeedsAPlaceToKeepTheOriginalAndAFormatOfItsOwn() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let document = EditorDocument(base: plainImage(), annotations: [arrow])
    let png = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: plainImage(), scale: 1)).write(to: png)
    #expect(try VersionWriter.saveImage(document, of: png, overwriting: true, scale: 1).url.lastPathComponent == "Shot (2).png")

    let heic = folder.appendingPathComponent("Photo.heic")
    try #require(ImageCodec.data(from: plainImage(), scale: 1)).write(to: heic)
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    #expect(try VersionWriter.saveImage(document, of: heic, overwriting: true, scale: 1, projects: store).url.lastPathComponent == "Photo (2).png")
}

@Test func pruningRemovesKeptOriginalsNoProjectNeedsAnymore() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: plainImage(), scale: 1)).write(to: original)
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let saved = try VersionWriter.saveImage(EditorDocument(base: plainImage(), annotations: [arrow]), of: original, overwriting: true, scale: 1, projects: store)

    store.prune()
    #expect(FileManager.default.fileExists(atPath: saved.original.path))
    try FileManager.default.removeItem(at: original)
    store.prune()
    #expect(!FileManager.default.fileExists(atPath: saved.original.path))
}

@Test func aJPEGVersionStaysJPEGAndStillGivesAPNGForTheClipboard() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("Shot.jpeg")
    try #require(ImageCodec.data(from: plainImage(), scale: 1, format: .jpeg)).write(to: original)
    let document = EditorDocument(base: plainImage(), annotations: [arrow], background: EditorDocument.defaultBackground(for: .jpeg))

    let saved = try VersionWriter.saveImage(document, of: original, scale: 1)
    #expect(saved.url.lastPathComponent == "Shot (2).jpeg")
    #expect(ImageCodec.image(from: saved.png) != nil)
    #expect(try Data(contentsOf: saved.url) != saved.png)
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

@Test func aSavedVersionsLayersComeBackLive() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let original = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: plainImage(), scale: 2)).write(to: original)
    // A placed image, a spotlight, a hidden and a styled layer, a styled screenshot.
    var document = EditorDocument(base: plainImage(), annotations: [arrow])
    document.addImage(plainImage(width: 20, height: 20), scale: 2, documentScale: 2, centeredAt: CGPoint(x: 30, y: 30), margin: 16)
    document.annotations.append(Annotation(kind: .spotlight(CGRect(x: 5, y: 5, width: 40, height: 30), style: SpotlightStyle()), color: RGBA(0, 0, 0), lineWidth: 0))
    document.annotations[0].isHidden = true
    document.annotations[1].style = ObjectStyle(shadow: Shadow(elevation: 8, opacity: 0.3))
    document.setCornerRadius(12, of: .capture)
    document.background = RGBA(0.2, 0.4, 0.6)

    let saved = try VersionWriter.saveImage(document, of: original, scale: 2, projects: store)
    let reopened = try #require(VersionWriter.layers(of: saved.url, in: store))
    #expect(reopened.original.resolvingSymlinksInPath() == original.resolvingSymlinksInPath())
    #expect(reopened.layers == document.snapshot)
    #expect(store.entry(for: saved.url) != nil)
}

@Test func aVersionOpensFlatWhenItsOriginalIsReplacedButFollowsItWhenMoved() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let original = folder.appendingPathComponent("Shot.png")
    try #require(ImageCodec.data(from: plainImage(), scale: 1)).write(to: original)
    let saved = try VersionWriter.saveImage(EditorDocument(base: plainImage(), annotations: [arrow]), of: original, scale: 1, projects: store)

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
    let saved = try VersionWriter.saveImage(EditorDocument(base: plainImage(), annotations: [arrow]), of: original, scale: 1)
    #expect(ImageCodec.projectID(ofFileAt: saved.url) == nil)
}

// MARK: Video projects

/// A recording with an import beside it, the import on its own track with a keyframe, its border and corners styled,
/// and an arrow over both: more than a trim, so it's drawn and re-encoded.
private func editedProject(recording: URL, overlay: URL) throws -> Project {
    var project = Project(source: recording, duration: 2, canvasSize: CGSize(width: 160, height: 90), hasAudio: false)
    let imported = try #require(project.importing(ImportedMedia(source: overlay, duration: 1, size: CGSize(width: 80, height: 45), hasAudio: false), at: 0.5))
    project = imported.project
    let track = try #require(project.tracks.firstIndex { $0.clips.contains { $0.id == imported.clip } })
    project.tracks[track].clips[0].animation.opacity = [Keyframe(time: 0, value: 0), Keyframe(time: 0.5, value: 1)]
    project.tracks[track].clips[0].style = ObjectStyle(shadow: Shadow(elevation: 8, opacity: 0.3))
    project.tracks[track].clips[0].cornerRadius = 6
    project.tracks.append(Track(kind: .overlay, annotations: [AnnotationClip(annotation: arrow, start: 0.25, duration: 1)]))
    return project
}

/// `project` with its sources' symlinks resolved, since the bookmark that finds the recording gives /private/var for /var.
private func resolved(_ project: Project) -> Project {
    var project = project
    for track in project.tracks.indices {
        for clip in project.tracks[track].clips.indices {
            project.tracks[track].clips[clip].source.resolveSymlinksInPath()
        }
    }
    return project
}

@Test func removingTheClipsOfAMissingFileTakesTheirPartnersAndKeepsTheRecording() throws {
    let recording = URL(fileURLWithPath: "/tmp/recording.mov"), gone = URL(fileURLWithPath: "/tmp/gone.mov")
    let base = Project(source: recording, duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: true)
    let media = ImportedMedia(source: gone, duration: 4, size: CGSize(width: 640, height: 360), hasAudio: true)
    let overlaid = try #require(base.importing(media, at: 3)).project
    #expect(overlaid.removingClips(from: [gone]) == base)
    // On the main track, its gap closes.
    let appended = try #require(base.appending(media)).project
    #expect(appended.removingClips(from: [gone]) == base)
    // The recording itself gone leaves nothing to play.
    #expect(base.removingClips(from: [recording]) == nil)
}

extension CompositingMediaTests {
    @Test func anExportedVideoAndGIFReopenWithTheirProjectLive() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
        let recording = folder.appendingPathComponent("Recording.mp4"), overlay = folder.appendingPathComponent("Overlay.mp4")
        try await writeSyntheticVideo(to: recording, seconds: 2, fps: 10, width: 160, height: 90)
        try await writeSyntheticVideo(to: overlay, seconds: 1, fps: 10, width: 80, height: 45)
        let project = try editedProject(recording: recording, overlay: overlay)

        let copy = VersionWriter.videoCopyURL(of: recording, prefix: "Shot")
        try await VersionWriter.writeVideo(VersionWriter.videoPlan(for: project, of: recording), of: project, original: recording, to: copy, projects: store)
        #expect(ProjectStamp.id(ofFileAt: copy) != nil)
        #expect(store.entry(for: copy) != nil)
        let reopened = try #require(VersionWriter.project(of: copy, in: store))
        #expect(reopened.original.resolvingSymlinksInPath() == recording.resolvingSymlinksInPath())
        #expect(resolved(reopened.project) == resolved(project))
        #expect(reopened.missing.isEmpty)

        // A GIF can't hold a stamp, so its project is found by the file's identity.
        let gif = folder.appendingPathComponent("Shot.gif")
        let options = VideoExportOptions(format: .gif)
        try await VersionWriter.writeVideo(VideoExportPlan(project: project, options: options), of: project, original: recording, to: gif, projects: store)
        #expect(resolved(try #require(VersionWriter.project(of: gif, in: store)).project) == resolved(project))

        // The recording itself has no project, so it opens as itself.
        #expect(VersionWriter.project(of: recording, in: store) == nil)
    }

    @Test func aVideoProjectFollowsItsFolderAndLeavesOutAnImportThatsGone() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(folder: root.appendingPathComponent("Projects"))
        let folder = root.appendingPathComponent("Captures")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Clips"), withIntermediateDirectories: true)
        let recording = folder.appendingPathComponent("Recording.mp4"), overlay = folder.appendingPathComponent("Clips/Overlay.mp4")
        try await writeSyntheticVideo(to: recording, seconds: 2, fps: 10, width: 160, height: 90)
        try await writeSyntheticVideo(to: overlay, seconds: 1, fps: 10, width: 80, height: 45)
        let project = try editedProject(recording: recording, overlay: overlay)
        let copy = folder.appendingPathComponent("Copy.mp4")
        try await VersionWriter.writeVideo(VersionWriter.videoPlan(for: project, of: recording), of: project, original: recording, to: copy, projects: store)

        // The whole folder moved: the recording by its bookmark, the import by where it was beside the recording.
        let moved = root.appendingPathComponent("Moved")
        try FileManager.default.moveItem(at: folder, to: moved)
        let followed = try #require(VersionWriter.project(of: moved.appendingPathComponent("Copy.mp4"), in: store))
        let sources = Set(followed.project.tracks.flatMap(\.clips).map { $0.source.resolvingSymlinksInPath().path })
        #expect(sources == Set(["Recording.mp4", "Clips/Overlay.mp4"].map { moved.appendingPathComponent($0).resolvingSymlinksInPath().path }))
        #expect(followed.missing.isEmpty)

        // With the import gone, its clip is left out and the rest, the arrow included, is kept.
        try FileManager.default.removeItem(at: moved.appendingPathComponent("Clips"))
        let partial = try #require(VersionWriter.project(of: moved.appendingPathComponent("Copy.mp4"), in: store))
        #expect(partial.missing.map(\.lastPathComponent) == ["Overlay.mp4"])
        #expect(partial.project.tracks.flatMap(\.clips).count == 1)
        #expect(partial.project.tracks.flatMap(\.annotations).count == 1)

        // Another recording where the original was isn't what the edit was made over, so the copy opens as itself.
        try FileManager.default.removeItem(at: moved.appendingPathComponent("Recording.mp4"))
        try await writeSyntheticVideo(to: moved.appendingPathComponent("Recording.mp4"), seconds: 3, fps: 10, width: 160, height: 90)
        #expect(VersionWriter.project(of: moved.appendingPathComponent("Copy.mp4"), in: store) == nil)
    }
}
