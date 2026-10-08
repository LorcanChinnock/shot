import Foundation
import Testing
@testable import ShotCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}()

private func day(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

// Wednesday 7 October 2026.
private let now = day(10, 7)

private func item(_ name: String, _ date: Date, bytes: Int = 1) -> GalleryItem {
    let kind = GalleryKind(fileExtension: (name as NSString).pathExtension)!
    return GalleryItem(url: URL(fileURLWithPath: "/shots/\(name)"), kind: kind, date: date, bytes: bytes)
}

@Test func kindFromExtension() {
    #expect(GalleryKind(fileExtension: "png") == .image)
    #expect(GalleryKind(fileExtension: "JPG") == .image)
    #expect(GalleryKind(fileExtension: "mp4") == .video)
    #expect(GalleryKind(fileExtension: "mov") == .video)
    #expect(GalleryKind(fileExtension: "gif") == .gif)
    #expect(GalleryKind(fileExtension: "txt") == nil)
    #expect(GalleryKind(fileExtension: "") == nil)
    #expect(GalleryKind.gif.isEditable == false)
    #expect(GalleryKind.video.isEditable)
}

@Test func filterAndSearch() {
    let items = [item("a.png", now), item("b.mp4", now), item("c.gif", now), item("Meeting notes.png", now)]
    #expect(Gallery.visible(items, filter: .screenshots, sort: .name, query: "").map(\.name) == ["a.png", "Meeting notes.png"])
    #expect(Gallery.visible(items, filter: .videos, sort: .name, query: "").map(\.name) == ["b.mp4"])
    #expect(Gallery.visible(items, filter: .gifs, sort: .name, query: "").map(\.name) == ["c.gif"])
    #expect(Gallery.visible(items, filter: .all, sort: .name, query: "  MEETING ").map(\.name) == ["Meeting notes.png"])
}

@Test func sorting() {
    let items = [item("b.png", day(10, 1), bytes: 5), item("a.png", day(10, 3), bytes: 9), item("c10.png", day(10, 2), bytes: 7), item("c2.png", day(10, 2), bytes: 7)]
    #expect(Gallery.visible(items, filter: .all, sort: .newest, query: "").map(\.name) == ["a.png", "c10.png", "c2.png", "b.png"])
    #expect(Gallery.visible(items, filter: .all, sort: .oldest, query: "").map(\.name) == ["b.png", "c10.png", "c2.png", "a.png"])
    #expect(Gallery.visible(items, filter: .all, sort: .name, query: "").map(\.name) == ["a.png", "b.png", "c2.png", "c10.png"])
    #expect(Gallery.visible(items, filter: .all, sort: .size, query: "").map(\.name) == ["a.png", "c10.png", "c2.png", "b.png"])
}

@Test func daySections() {
    let items = [
        item("today.png", day(10, 7, hour: 9)),
        item("yesterday.png", day(10, 6)),
        item("week.png", day(10, 5)),
        item("month.png", day(10, 1)),
        item("sep.png", day(9, 30)),
        item("sep2.png", day(9, 2)),
        item("old.png", day(1, 15)),
    ]
    let sections = Gallery.sections(items, sort: .newest, now: now, calendar: calendar)
    #expect(sections.map(\.title) == ["Today", "Yesterday", "This Week", "This Month", "September 2026", "January 2026"])
    #expect(sections[4].items.map(\.name) == ["sep.png", "sep2.png"])
}

@Test func daySectionsSplitAtExactBoundaries() {
    let items = [
        item("midnight.png", day(10, 7, hour: 0)),
        item("last-yesterday.png", day(10, 7, hour: 0).addingTimeInterval(-1)),
        item("first-oct.png", day(10, 1, hour: 0)),
        item("last-sep.png", day(10, 1, hour: 0).addingTimeInterval(-1)),
        item("first-sep.png", day(9, 1, hour: 0)),
        item("last-aug.png", day(9, 1, hour: 0).addingTimeInterval(-1)),
        item("dec.png", day(12, 31).addingTimeInterval(-366 * 86_400)),
    ]
    let expected = ["Today", "Yesterday", "This Month", "September 2026", "August 2026", "December 2025"]
    #expect(Gallery.sections(items, sort: .newest, now: now, calendar: calendar).map(\.title) == expected)
    #expect(Gallery.sections(items.reversed(), sort: .oldest, now: now, calendar: calendar).map(\.title) == expected.reversed())
}

@Test func nonDateSortIsOneSection() {
    let items = [item("a.png", now), item("b.png", day(1, 1))]
    #expect(Gallery.sections(items, sort: .name, now: now, calendar: calendar).map(\.items.count) == [2])
    #expect(Gallery.sections([], sort: .name, now: now, calendar: calendar).isEmpty)
    #expect(Gallery.sections([], sort: .newest, now: now, calendar: calendar).isEmpty)
}

@Test func renameKeepsExtensionAndCleansName() {
    let url = URL(fileURLWithPath: "/shots/old.png")
    #expect(Gallery.renamedURL(of: url, to: "new")?.lastPathComponent == "new.png")
    #expect(Gallery.renamedURL(of: url, to: "new.PNG")?.lastPathComponent == "new.png")
    #expect(Gallery.renamedURL(of: url, to: "  a/b:c  ")?.lastPathComponent == "a-b-c.png")
    #expect(Gallery.renamedURL(of: url, to: "   ") == nil)
    #expect(Gallery.renamedURL(of: url, to: ".hidden") == nil)
    #expect(Gallery.renamedURL(of: url, to: "x")?.deletingLastPathComponent().path == "/shots")
}

@Test func restoreMovesFilesBackAndSkipsTakenPaths() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let bin = root.appendingPathComponent("bin")
    try manager.createDirectory(at: bin, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let moves = ["a.png", "b.png"].map { (trashed: bin.appendingPathComponent($0), original: root.appendingPathComponent($0)) }
    for move in moves {
        try Data([1]).write(to: move.trashed)
    }
    try Data([2]).write(to: moves[1].original)

    #expect(Gallery.restore(moves) == [moves[0].original])
    #expect(manager.fileExists(atPath: moves[0].original.path))
    #expect(manager.fileExists(atPath: moves[1].trashed.path))
    #expect(try Data(contentsOf: moves[1].original) == Data([2]))
}

@Test func arrowMovementClamps() {
    #expect(Gallery.moved(from: nil, by: 1, count: 5) == 0)
    #expect(Gallery.moved(from: nil, by: -1, count: 5) == 4)
    #expect(Gallery.moved(from: 2, by: 3, count: 5) == 4)
    #expect(Gallery.moved(from: 2, by: -3, count: 5) == 0)
    #expect(Gallery.moved(from: 0, by: 1, count: 0) == nil)
}

@Test func verticalMovementFollowsTheSectionRows() {
    // Sections of 5 and 3 items in 2 columns: rows are [0 1] [2 3] [4] then [5 6] [7].
    let sizes = [5, 3]
    #expect(Gallery.movedVertically(from: 0, sectionSizes: sizes, down: true, columns: 2) == 2)
    #expect(Gallery.movedVertically(from: 3, sectionSizes: sizes, down: true, columns: 2) == 4)
    #expect(Gallery.movedVertically(from: 4, sectionSizes: sizes, down: true, columns: 2) == 5)
    #expect(Gallery.movedVertically(from: 5, sectionSizes: sizes, down: false, columns: 2) == 4)
    #expect(Gallery.movedVertically(from: 6, sectionSizes: sizes, down: false, columns: 2) == 4)
    #expect(Gallery.movedVertically(from: 7, sectionSizes: sizes, down: false, columns: 2) == 5)
    #expect(Gallery.movedVertically(from: 6, sectionSizes: sizes, down: true, columns: 2) == 7)
    #expect(Gallery.movedVertically(from: 7, sectionSizes: sizes, down: true, columns: 2) == 7)
    #expect(Gallery.movedVertically(from: 1, sectionSizes: sizes, down: false, columns: 2) == 1)
    #expect(Gallery.movedVertically(from: nil, sectionSizes: sizes, down: false, columns: 2) == 7)
    #expect(Gallery.movedVertically(from: nil, sectionSizes: [], down: true, columns: 2) == nil)
}

@Test func verticalMovementIntoAShortRowLandsOnTheLastItem() {
    // One section of 5 in 3 columns: rows are [0 1 2] [3 4].
    #expect(Gallery.movedVertically(from: 2, sectionSizes: [5], down: true, columns: 3) == 4)
    #expect(Gallery.movedVertically(from: 4, sectionSizes: [5], down: false, columns: 3) == 1)
}

@Test func durationLabel() {
    #expect(Gallery.duration(5) == "0:05")
    #expect(Gallery.duration(75.4) == "1:15")
    #expect(Gallery.duration(3725) == "1:02:05")
}

@Test func listsOnlyMediaInFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gallery-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["a.png", "b.mp4", "c.gif", "notes.txt", ".hidden.png"] {
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent(name))
    }
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub.png"), withIntermediateDirectories: false)
    let names = Gallery.items(in: folder).map(\.name).sorted()
    #expect(names == ["a.png", "b.mp4", "c.gif"])
    #expect(Gallery.items(in: folder.appendingPathComponent("missing")).isEmpty)
}

@Test func toggleAddsOrRemovesOneItem() {
    let a = URL(fileURLWithPath: "/shots/a.png")
    let b = URL(fileURLWithPath: "/shots/b.png")
    #expect(Gallery.toggled([a], b) == [a, b])
    #expect(Gallery.toggled([a, b], b) == [a])
    #expect(Gallery.toggled([], a) == [a])
}

@Test func allSelectedNeedsEveryVisibleItem() {
    let visible = [item("a.png", now), item("b.mp4", now)]
    #expect(Gallery.allSelected(Set(visible.map(\.url)), in: visible))
    #expect(!Gallery.allSelected([visible[0].url], in: visible))
    #expect(!Gallery.allSelected([], in: visible))
    #expect(!Gallery.allSelected([], in: []))
}

@Test func editNeedsEveryItemEditable() {
    #expect(Gallery.canEdit([item("a.png", now), item("b.mp4", now)]))
    #expect(!Gallery.canEdit([item("a.png", now), item("c.gif", now)]))
    #expect(!Gallery.canEdit([]))
}
