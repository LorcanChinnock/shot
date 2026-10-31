import Foundation
import Testing
@testable import ShotCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func item(_ name: String, folder: String = "") -> GalleryItem {
    let directory = folder.isEmpty ? "/shots" : "/shots/\(folder)"
    let kind = GalleryKind(fileExtension: (name as NSString).pathExtension)!
    return GalleryItem(url: URL(fileURLWithPath: "\(directory)/\(name)"), kind: kind, date: now, bytes: 1, folder: folder)
}

@Test func theGalleryListsTheFoldersInTheSaveFolderAtAnyDepth() throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = FileManager.default
    for folder in ["Clients", "Bugs 10", "Bugs 9", ".hidden", "Clients/Acme", "Photos.app"] {
        try manager.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    for path in ["top.png", "Clients/a.png", "Clients/notes.txt", "Clients/Acme/deep.png", ".hidden/secret.png", "Bugs 9/b.mp4", "Photos.app/inside.png"] {
        try Data([1, 2, 3]).write(to: root.appendingPathComponent(path))
    }

    #expect(Gallery.folders(in: root) == ["Bugs 9", "Bugs 10", "Clients", "Clients/Acme"])
    let items = Gallery.items(in: root)
    #expect(Set(items.map { "\($0.folder)/\($0.name)" }) == ["/top.png", "Clients/a.png", "Clients/Acme/deep.png", "Bugs 9/b.mp4"])
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
    #expect(prefs.isOwnCapture(root.appendingPathComponent("Clients/Acme/a.png")))
    #expect(!prefs.isOwnCapture(root.deletingLastPathComponent().appendingPathComponent("\(root.lastPathComponent)-other/a.png")))
    #expect(!prefs.isOwnCapture(root.deletingLastPathComponent().appendingPathComponent("a.png")))

    #expect(prefs.captureFolder.path == root.path)
    suite.store.set("Clients", forKey: PreferenceKey.captureSubfolder)
    #expect(prefs.captureFolder.path == root.appendingPathComponent("Clients").path)
}

@Test func foldersNestAndPathsSplitIntoNames() {
    let root = URL(fileURLWithPath: "/shots")
    #expect(Gallery.folderURL("Clients/Acme", in: root).path == "/shots/Clients/Acme")
    #expect(Gallery.folderPath("Acme", in: "Clients") == "Clients/Acme")
    #expect(Gallery.folderPath("Clients", in: "") == "Clients")
    #expect(Gallery.parentFolder(of: "Clients/Acme") == "Clients")
    #expect(Gallery.parentFolder(of: "Clients").isEmpty)
    #expect(Gallery.folderLeaf(of: "Clients/Acme") == "Acme")
    #expect(Gallery.ancestors(of: "Clients/Acme/Q1") == ["Clients", "Clients/Acme"])
    #expect(Gallery.ancestors(of: "Clients").isEmpty)
    #expect(Gallery.folder("Clients/Acme", isIn: "Clients"))
    #expect(!Gallery.folder("Clients 2", isIn: "Clients"))
}

@Test func newCapturesFindTheirFolderWhenItsRenamedOrMoved() {
    #expect(Gallery.relocated("Clients", from: "Clients", to: "Work/Clients") == "Work/Clients")
    #expect(Gallery.relocated("Clients/Acme", from: "Clients", to: "Customers") == "Customers/Acme")
    #expect(Gallery.relocated("Clients 2", from: "Clients", to: "Customers") == "Clients 2")
    #expect(Gallery.relocated("", from: "Clients", to: "Customers").isEmpty)
}

@Test func aFoldersContentsCountEverythingInsideIt() {
    let items = [item("a.png"), item("b.png", folder: "Clients"), item("c.png", folder: "Clients/Acme"), item("d.png", folder: "Bugs")]
    let counts = Gallery.contents(of: "Clients", items: items, folders: ["Bugs", "Clients", "Clients/Acme", "Clients/Acme/Q1"])
    #expect(counts.captures == 2)
    #expect(counts.folders == 2)
}

@Test func makingRenamingAndMovingNestedFolders() throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = FileManager.default

    #expect(try Gallery.createFolder(" Clients ", in: "", root: root) == "Clients")
    #expect(try Gallery.createFolder("Acme", in: "Clients", root: root) == "Clients/Acme")
    #expect(throws: GalleryFolderError.exists) { try Gallery.createFolder("Acme", in: "Clients", root: root) }
    #expect(throws: GalleryFolderError.invalidName) { try Gallery.createFolder(".hidden", in: "", root: root) }
    try Data([1]).write(to: root.appendingPathComponent("Clients/Acme/a.png"))

    #expect(try Gallery.renameFolder("Clients/Acme", to: "Globex", root: root) == "Clients/Globex")
    #expect(manager.fileExists(atPath: root.appendingPathComponent("Clients/Globex/a.png").path))
    #expect(try Gallery.renameFolder("Clients", to: "clients", root: root) == "clients")
    #expect(throws: GalleryFolderError.invalidName) { try Gallery.renameFolder("clients", to: "  ", root: root) }

    _ = try Gallery.createFolder("Bugs", in: "", root: root)
    #expect(throws: GalleryFolderError.exists) { try Gallery.renameFolder("Bugs", to: "clients", root: root) }
    #expect(throws: GalleryFolderError.intoItself) { try Gallery.moveFolder("clients", into: "clients/Globex", root: root) }
    #expect(try Gallery.moveFolder("Bugs", into: "clients", root: root) == "clients/Bugs")
    #expect(Gallery.folders(in: root) == ["clients", "clients/Bugs", "clients/Globex"])
    #expect(throws: GalleryFolderError.missing) { try Gallery.renameFolder("Gone", to: "x", root: root) }
}
