import Foundation
import Testing
@testable import ShotCore

private func item(_ name: String, bytes: Int, day: Double = 0) -> GalleryItem {
    GalleryItem(url: URL(fileURLWithPath: "/captures/\(name)"), kind: .image, date: Date(timeIntervalSince1970: day * 86_400), bytes: bytes)
}

@Test func makeRoomLargeIsOverTwentyFiveMegabytesLargestFirst() {
    let items = [item("a", bytes: 3_000_000), item("b", bytes: 25_000_000), item("c", bytes: 25_000_001), item("d", bytes: 90_000_000)]
    #expect(MakeRoom.large(items).map(\.name) == ["d", "c"])
    #expect(MakeRoom.bytes(MakeRoom.large(items)) == 115_000_001)
}

@Test func makeRoomLargeLeavesOutCopiesListedAsDuplicates() {
    let original = item("original", bytes: 50_000_000, day: 1), copy = item("copy", bytes: 50_000_000, day: 2)
    #expect(MakeRoom.large([original, copy], excluding: [copy]).map(\.name) == ["original"])
}

@Test func makeRoomKeepsTheOldestOfEachSetOfCopies() {
    let items = [item("new", bytes: 10, day: 3), item("old", bytes: 10, day: 1), item("mid", bytes: 10, day: 2), item("other", bytes: 10, day: 0)]
    let prints = ["new": "x", "old": "x", "mid": "x", "other": "y"]
    let copies = MakeRoom.duplicateCopies(items) { prints[$0.lastPathComponent] }
    #expect(Set(copies.map(\.name)) == ["new", "mid"])
}

@Test func makeRoomKeepsTheOldestCopyLeftOnceTheOriginalHasGone() {
    let original = item("original", bytes: 50_000_000, day: 1)
    let first = item("first", bytes: 50_000_000, day: 2), second = item("second", bytes: 50_000_000, day: 3)
    let all = MakeRoom.duplicateCopies([original, first, second]) { _ in "same" }
    #expect(Set(all.map(\.name)) == ["first", "second"])
    // The original is large, so Large captures lists it, and trashing that group takes it.
    #expect(MakeRoom.large([original, first, second], excluding: all).map(\.name) == ["original"])
    // Checked again without it, the oldest copy left is the one kept.
    #expect(MakeRoom.duplicateCopies([first, second]) { _ in "same" }.map(\.name) == ["second"])
}

@Test func makeRoomOnlyReadsFilesThatShareASize() {
    var read: [String] = []
    let items = [item("a", bytes: 10), item("b", bytes: 20), item("c", bytes: 20), item("empty", bytes: 0), item("empty2", bytes: 0)]
    let copies = MakeRoom.duplicateCopies(items) { url in
        read.append(url.lastPathComponent)
        return "same"
    }
    #expect(Set(read) == ["b", "c"])
    #expect(copies.count == 1)
}

@Test func makeRoomNeverCountsAFileItCantReadAsACopy() {
    let items = [item("a", bytes: 10, day: 1), item("b", bytes: 10, day: 2)]
    #expect(MakeRoom.duplicateCopies(items) { _ in nil }.isEmpty)
}

@Test func makeRoomFingerprintMatchesIdenticalFilesOnly() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let one = folder.appendingPathComponent("one.png"), two = folder.appendingPathComponent("two.png"), three = folder.appendingPathComponent("three.png")
    try Data("same pixels".utf8).write(to: one)
    try Data("same pixels".utf8).write(to: two)
    try Data("same pixelz".utf8).write(to: three)
    #expect(MakeRoom.fingerprint(of: one) != nil)
    #expect(MakeRoom.fingerprint(of: one) == MakeRoom.fingerprint(of: two))
    #expect(MakeRoom.fingerprint(of: one) != MakeRoom.fingerprint(of: three))
    #expect(MakeRoom.fingerprint(of: folder.appendingPathComponent("missing.png")) == nil)
}
