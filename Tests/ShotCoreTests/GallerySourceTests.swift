import Foundation
import Testing
@testable import ShotCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func item(_ name: String, folder: String = "", bytes: Int = 10) -> GalleryItem {
    let kind = GalleryKind(fileExtension: (name as NSString).pathExtension)!
    let path = folder.isEmpty ? "/shots/\(name)" : "/shots/\(folder)/\(name)"
    return GalleryItem(url: URL(fileURLWithPath: path), kind: kind, date: now, bytes: bytes, folder: folder)
}

@Test func gallerySourceSetsOneScopeAtATime() {
    #expect(GallerySource.all.filter == .all)
    #expect(GallerySource.all.folder == nil)
    #expect(GallerySource.all.tags.isEmpty)
    #expect(GallerySource.library(.gifs).filter == .gifs)
    #expect(GallerySource.library(.gifs).folder == nil)
    #expect(GallerySource.folder("Bugs").filter == .all)
    #expect(GallerySource.folder("Bugs").folder == "Bugs")
    #expect(GallerySource.folder("").folder == "")
    #expect(GallerySource.tag("Docs").tags == ["Docs"])
    #expect(GallerySource.tag("Docs").filter == .all)
    #expect(GallerySource.tag("Docs").folder == nil)
}

@Test func gallerySourceScopeMatchesWhatTheGridShows() {
    let items = [item("a.png"), item("b.mp4", folder: "Bugs"), item("c.gif", folder: "Bugs/Old")]
    let tags = [items[0].url: ["Docs"], items[2].url: ["docs"]]
    func shown(_ source: GallerySource) -> [String] {
        Gallery.visible(items, filter: source.filter, sort: .name, query: "", folder: source.folder, tags: source.tags, tagsOf: tags).map(\.name)
    }
    #expect(shown(.all) == ["a.png", "b.mp4", "c.gif"])
    #expect(shown(.library(.videos)) == ["b.mp4"])
    #expect(shown(.folder("")) == ["a.png"])
    #expect(shown(.folder("Bugs")) == ["b.mp4"])
    #expect(shown(.tag("DOCS")) == ["a.png", "c.gif"])
}

@Test func galleryCountsEachRowOnce() {
    let items = [item("a.png", bytes: 100), item("b.png", folder: "Bugs", bytes: 50), item("c.mp4", folder: "Bugs", bytes: 1000), item("d.gif", folder: "Bugs/Old", bytes: 5)]
    let tags = [items[0].url: ["Docs", "docs"], items[1].url: ["Bug"], items[3].url: ["DOCS"]]
    let counts = GalleryCounts(items, tagsOf: tags)
    #expect(counts.count(of: .all) == 4)
    #expect(counts.count(of: .library(.screenshots)) == 2)
    #expect(counts.count(of: .library(.videos)) == 1)
    #expect(counts.count(of: .library(.gifs)) == 1)
    #expect(counts.count(of: .folder("")) == 1)
    #expect(counts.count(of: .folder("Bugs")) == 2)
    #expect(counts.count(of: .folder("Bugs/Old")) == 1)
    #expect(counts.count(of: .folder("Nowhere")) == 0)
    // A capture tagged "Docs" and "docs" counts once.
    #expect(counts.count(of: .tag("Docs")) == 2)
    #expect(counts.count(ofTag: "bug") == 1)
    #expect(counts.count(ofTag: "Shipped") == 0)
    #expect(counts.bytes == 1155)
}

@Test func galleryCountsStartAtZeroForAnEmptyLibrary() {
    let counts = GalleryCounts([], tagsOf: [:])
    #expect(counts.count(of: .all) == 0)
    #expect(counts.count(of: .library(.gifs)) == 0)
    #expect(counts.bytes == 0)
    #expect(GalleryCounts.empty.count(of: .all) == 0)
}

@Test func galleryCountsShareOfTheDisk() {
    let counts = GalleryCounts([item("a.png", bytes: 250)], tagsOf: [:])
    #expect(abs(counts.share(ofCapacity: 1000) - 0.25) < 0.0001)
    #expect(counts.share(ofCapacity: 100) == 1)
    #expect(counts.share(ofCapacity: nil) == 0)
    #expect(counts.share(ofCapacity: 0) == 0)
}

@Test func galleryLibraryTitlesNameRecordings() {
    #expect(GalleryFilter.all.libraryTitle == "All Captures")
    #expect(GalleryFilter.videos.libraryTitle == "Recordings")
}
