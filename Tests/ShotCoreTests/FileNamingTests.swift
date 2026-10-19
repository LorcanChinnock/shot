import Foundation
import Testing
@testable import ShotCore

private let date: Date = {
    var components = DateComponents()
    components.year = 2026; components.month = 10; components.day = 2
    components.hour = 14; components.minute = 3; components.second = 11
    return Calendar.current.date(from: components)!
}()

@Test func baseNameFormat() {
    #expect(FileNaming.baseName(for: date) == "Shot 2026-10-02 at 14.03.11")
}

@Test func uniqueURLAddsCollisionSuffixes() {
    let folder = URL(fileURLWithPath: "/tmp/shots")
    let taken: Set<String> = ["Shot 2026-10-02 at 14.03.11.png", "Shot 2026-10-02 at 14.03.11 (2).png"]
    let url = FileNaming.uniqueURL(in: folder, date: date, pathExtension: "png") { taken.contains($0.lastPathComponent) }
    #expect(url.lastPathComponent == "Shot 2026-10-02 at 14.03.11 (3).png")
    let free = FileNaming.uniqueURL(in: folder, date: date, pathExtension: "mp4") { _ in false }
    #expect(free.lastPathComponent == "Shot 2026-10-02 at 14.03.11.mp4")
}

@Test func customPrefix() {
    #expect(FileNaming.baseName(for: date, prefix: "Bug") == "Bug 2026-10-02 at 14.03.11")
}

@Test func recoveredNamesSayRecoveredAndAvoidCollisions() {
    let folder = URL(fileURLWithPath: "/tmp/shots")
    #expect(FileNaming.recoveredURL(in: folder, date: date) { _ in false }.lastPathComponent == "Shot 2026-10-02 at 14.03.11 (recovered).mp4")
    #expect(FileNaming.recoveredURL(in: folder, date: date, part: 2) { _ in false }.lastPathComponent == "Shot 2026-10-02 at 14.03.11 (recovered, part 2).mp4")
    let taken: Set<String> = ["Shot 2026-10-02 at 14.03.11 (recovered).mp4"]
    #expect(FileNaming.recoveredURL(in: folder, date: date) { taken.contains($0.lastPathComponent) }.lastPathComponent == "Shot 2026-10-02 at 14.03.11 (recovered) (2).mp4")
}

@Test func writeNewWritesTheWholeFileAndLeavesNoTemporaryBehind() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("naming-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let data = Data(repeating: 7, count: 100_000)
    let url = try FileNaming.writeNew(data, in: folder) { folder.appendingPathComponent("a.png") }
    #expect(url.lastPathComponent == "a.png")
    #expect(try Data(contentsOf: url) == data)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["a.png"])
}

@Test func writeNewNeverReplacesAFileAndAsksForAnotherName() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("naming-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let taken = folder.appendingPathComponent("a.png")
    try Data("first".utf8).write(to: taken)
    var names = [taken, folder.appendingPathComponent("a (2).png")].makeIterator()
    let url = try FileNaming.writeNew(Data("second".utf8), in: folder) { names.next()! }
    #expect(url.lastPathComponent == "a (2).png")
    #expect(try Data(contentsOf: taken) == Data("first".utf8))
    #expect(try Data(contentsOf: url) == Data("second".utf8))
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["a.png", "a (2).png"])
}

@Test func writeNewThrowsWhenTheFolderIsMissing() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
    #expect(throws: (any Error).self) {
        try FileNaming.writeNew(Data("x".utf8), in: folder) { folder.appendingPathComponent("a.png") }
    }
}

@Test func renamingExclusivelyRefusesToReplaceAFile() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source")
    let target = folder.appendingPathComponent("target")
    try Data("new".utf8).write(to: source)
    try Data("old".utf8).write(to: target)
    #expect(FileNaming.renameExclusively(source, to: target) == -1)
    #expect(errno == EEXIST)
    #expect(try Data(contentsOf: target) == Data("old".utf8))
    #expect(try Data(contentsOf: source) == Data("new".utf8))

    let free = folder.appendingPathComponent("free")
    #expect(FileNaming.renameExclusively(source, to: free) == 0)
    #expect(try Data(contentsOf: free) == Data("new".utf8))
    #expect(!FileManager.default.fileExists(atPath: source.path))
}
