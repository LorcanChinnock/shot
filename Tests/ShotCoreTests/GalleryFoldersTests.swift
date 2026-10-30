import Foundation
import Testing
@testable import ShotCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func item(_ name: String, folder: String = "") -> GalleryItem {
    let directory = folder.isEmpty ? "/shots" : "/shots/\(folder)"
    let kind = GalleryKind(fileExtension: (name as NSString).pathExtension)!
    return GalleryItem(url: URL(fileURLWithPath: "\(directory)/\(name)"), kind: kind, date: now, bytes: 1, folder: folder)
}

@Test func theGalleryListsTheFoldersInTheSaveFolderButNoDeeper() throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = FileManager.default
    for folder in ["Clients", "Bugs 10", "Bugs 9", ".hidden", "Clients/Acme", "Photos.app"] {
        try manager.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    for path in ["top.png", "Clients/a.png", "Clients/notes.txt", "Clients/Acme/deep.png", ".hidden/secret.png", "Bugs 9/b.mp4", "Photos.app/inside.png"] {
        try Data([1, 2, 3]).write(to: root.appendingPathComponent(path))
    }

    #expect(Gallery.folders(in: root) == ["Bugs 9", "Bugs 10", "Clients"])
    let items = Gallery.items(in: root)
    #expect(Set(items.map { "\($0.folder)/\($0.name)" }) == ["/top.png", "Clients/a.png", "Bugs 9/b.mp4"])
    #expect(Gallery.items(in: root, subfolders: false).map(\.name) == ["top.png"])
    #expect(Gallery.folders(in: root.appendingPathComponent("missing")).isEmpty)
}

@Test func aFolderShowsOnlyWhatsInItAndAllShowsEverything() {
    let items = [item("a.png"), item("b.png", folder: "Clients"), item("c.mp4", folder: "Bugs")]
    #expect(Gallery.visible(items, filter: .all, sort: .name, query: "").count == 3)
    #expect(Gallery.visible(items, filter: .all, sort: .name, query: "", folder: "Clients").map(\.name) == ["b.png"])
    #expect(Gallery.visible(items, filter: .all, sort: .name, query: "", folder: "").map(\.name) == ["a.png"])
    #expect(Gallery.visible(items, filter: .screenshots, sort: .name, query: "", folder: "Bugs").isEmpty)
}

@Test func folderNamesAreCleanedLikeFileNames() {
    #expect(Gallery.folderName("  Clients ") == "Clients")
    #expect(Gallery.folderName("a/b:c") == "a-b-c")
    #expect(Gallery.folderName("   ") == nil)
    #expect(Gallery.folderName(".secret") == nil)
    #expect(Gallery.folderName(String(repeating: "x", count: 500))?.count == Gallery.maxFolderName)
}

@Test func aMovePlanSkipsFilesAlreadyThereAndNamesThatAreTaken() {
    let root = URL(fileURLWithPath: "/shots")
    let clients = root.appendingPathComponent("Clients", isDirectory: true)
    let files = [
        root.appendingPathComponent("a.png"),
        clients.appendingPathComponent("b.png"),
        root.appendingPathComponent("taken.png"),
        root.appendingPathComponent("Bugs/a.png"),
    ]
    let plan = Gallery.movePlan(files, to: clients) { $0.lastPathComponent == "taken.png" }
    #expect(plan.moves.map(\.from) == [files[0]])
    #expect(plan.moves.map(\.to.path) == ["/shots/Clients/a.png"])
    // A second a.png can't take the first one's place.
    #expect(plan.taken == [files[2], files[3]])
}

@Test func movingFilesIntoAFolderAndBackOut() throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("a.png"), b = root.appendingPathComponent("b.png")
    try Data([1]).write(to: a)
    try Data([2]).write(to: b)
    let clients = Gallery.folderURL("Clients", in: root)
    try FileManager.default.createDirectory(at: clients, withIntermediateDirectories: true)
    try Data([3]).write(to: clients.appendingPathComponent("b.png"))

    let result = Gallery.move([a, b], to: clients)
    #expect(result.moved.map(\.to.lastPathComponent) == ["a.png"])
    #expect(result.taken == [b])
    #expect(result.failed.isEmpty)
    #expect(try Data(contentsOf: clients.appendingPathComponent("a.png")) == Data([1]))
    #expect(try Data(contentsOf: clients.appendingPathComponent("b.png")) == Data([3]))

    let back = Gallery.move([clients.appendingPathComponent("a.png")], to: Gallery.folderURL("", in: root))
    #expect(back.moved.count == 1)
    #expect(FileManager.default.fileExists(atPath: a.path))
}

@Test func movingIntoAFolderThatIsntThereYetMakesIt() throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("a.png")
    try Data([1]).write(to: a)
    let result = Gallery.move([a], to: Gallery.folderURL("New", in: root))
    #expect(result.moved.count == 1)
    #expect(Gallery.folders(in: root) == ["New"])
}

@Test func newCapturesGoToThePickedFolderOnlyWhileItsThere() throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Clients"), withIntermediateDirectories: true)
    try Data([1]).write(to: root.appendingPathComponent("file.png"))

    #expect(Gallery.captureFolder(in: root, subfolder: "") == root)
    #expect(Gallery.captureFolder(in: root, subfolder: "Clients") == root.appendingPathComponent("Clients", isDirectory: true))
    #expect(Gallery.captureFolder(in: root, subfolder: "Gone") == root)
    #expect(Gallery.captureFolder(in: root, subfolder: "file.png") == root)
    #expect(Gallery.captureFolder(in: root, subfolder: "../elsewhere") == root)
}

@Test func capturesInTheSaveFoldersFoldersAreShotsOwn() throws {
    let suite = try TestDefaults()
    defer { suite.remove() }
    Preferences.registerDefaults(in: suite.store)
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Clients"), withIntermediateDirectories: true)
    suite.store.set(root.path, forKey: PreferenceKey.saveFolder)
    let prefs = Preferences(store: suite.store)

    #expect(prefs.isOwnCapture(root.appendingPathComponent("a.png")))
    #expect(prefs.isOwnCapture(root.appendingPathComponent("Clients/a.png")))
    #expect(!prefs.isOwnCapture(root.appendingPathComponent("Clients/Acme/a.png")))
    #expect(!prefs.isOwnCapture(root.deletingLastPathComponent().appendingPathComponent("a.png")))

    #expect(prefs.captureFolder.path == root.path)
    suite.store.set("Clients", forKey: PreferenceKey.captureSubfolder)
    #expect(prefs.captureFolder.path == root.appendingPathComponent("Clients").path)
}
