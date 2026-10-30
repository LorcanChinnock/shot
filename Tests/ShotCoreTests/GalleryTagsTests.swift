import Foundation
import Testing
@testable import ShotCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func item(_ name: String) -> GalleryItem {
    let kind = GalleryKind(fileExtension: (name as NSString).pathExtension)!
    return GalleryItem(url: URL(fileURLWithPath: "/shots/\(name)"), kind: kind, date: now, bytes: 1)
}

@Test func aQuerySplitsTagsFromWords() {
    #expect(GalleryQuery("  invoice   42 ") == GalleryQuery("invoice 42"))
    #expect(GalleryQuery("invoice 42").text == "invoice 42")
    #expect(GalleryQuery("invoice 42").tags.isEmpty)
    let query = GalleryQuery("tag:Bug login TAG:\"Client A\" tag:")
    #expect(query.text == "login")
    #expect(query.tags == ["Bug", "Client A"])
    #expect(GalleryQuery("tag:\"half typed").tags == ["half typed"])
    #expect(GalleryQuery("hashtag:x").text == "hashtag:x")
}

@Test func tagsNarrowTheGalleryAndIgnoreCase() {
    let items = [item("a.png"), item("b.png"), item("c.mp4")]
    let tags = [items[0].url: ["Bug", "Acme"], items[1].url: ["bug"], items[2].url: ["Acme"]]
    #expect(Gallery.visible(items, filter: .all, sort: .name, query: "", tags: ["BUG"], tagsOf: tags).map(\.name) == ["a.png", "b.png"])
    #expect(Gallery.visible(items, filter: .all, sort: .name, query: "", tags: ["Bug", "Acme"], tagsOf: tags).map(\.name) == ["a.png"])
    #expect(Gallery.visible(items, filter: .videos, sort: .name, query: "tag:acme", tagsOf: tags).map(\.name) == ["c.mp4"])
    #expect(Gallery.visible(items, filter: .all, sort: .name, query: "tag:acme a", tagsOf: tags).map(\.name) == ["a.png"])
    #expect(Gallery.visible(items, filter: .all, sort: .name, query: "tag:", tagsOf: tags).count == 3)
}

@Test func everyTagIsListedOnceInFindersOrder() {
    let tags = [URL(fileURLWithPath: "/a"): ["bug", "Tag 10"], URL(fileURLWithPath: "/b"): ["Tag 9", "Acme"], URL(fileURLWithPath: "/c"): ["acme"]]
    let all = GalleryTags.all(tags)
    #expect(all.count == 4)
    #expect(all.map { $0.lowercased() } == ["acme", "bug", "tag 9", "tag 10"])
}

@Test func clickingATagAddsItUnlessEveryFileHasIt() {
    let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b")
    let tags = [a: ["Bug"], b: ["Acme"]]
    #expect(GalleryTags.coverage(of: "bug", on: [a, b], tagsOf: tags) == .some)
    #expect(GalleryTags.coverage(of: "Bug", on: [a], tagsOf: tags) == .all)
    #expect(GalleryTags.coverage(of: "Other", on: [a, b], tagsOf: tags) == .none)

    #expect(GalleryTags.toggling("Bug", on: [a, b], tagsOf: tags) == [b: ["Acme", "Bug"]])
    #expect(GalleryTags.toggling("BUG", on: [a], tagsOf: tags) == [a: []])
    #expect(GalleryTags.adding("bug", to: ["Bug"]) == ["Bug"])
    #expect(GalleryTags.removing("bug", from: ["Bug", "Acme"]) == ["Acme"])
}

@Test func tagsAreFinderTagsOnTheFile() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.png")
    try Data([1]).write(to: file)
    #expect(GalleryTags.tags(of: file).isEmpty)
    try GalleryTags.setTags(["Bug", "Client A"], of: file)
    #expect(Set(GalleryTags.tags(of: file)) == ["Bug", "Client A"])

    // They go wherever the file does.
    let moved = Gallery.move([file], to: Gallery.folderURL("Clients", in: folder))
    let there = try #require(moved.moved.first?.to)
    #expect(Set(GalleryTags.tags(of: there)) == ["Bug", "Client A"])
    try GalleryTags.setTags([], of: there)
    #expect(GalleryTags.tags(of: there).isEmpty)
}
