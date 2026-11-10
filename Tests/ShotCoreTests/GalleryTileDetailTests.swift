import Foundation
import Testing
@testable import ShotCore

private let gmt = TimeZone(identifier: "GMT")!
private let english = Locale(identifier: "en_GB")

private func tileItem(_ name: String, bytes: Int = 2_100_000) -> GalleryItem {
    let kind = GalleryKind(fileExtension: (name as NSString).pathExtension)!
    // 2026-11-10 21:53 GMT.
    return GalleryItem(url: URL(fileURLWithPath: "/shots/\(name)"), kind: kind, date: Date(timeIntervalSince1970: 1_794_347_580), bytes: bytes)
}

@Test func galleryTileDetailShowsTheTimeWhenSortedByDate() {
    #expect(Gallery.tileDetail(for: tileItem("a.png"), sort: .newest, locale: english, timeZone: gmt) == "PNG · 21:53")
    #expect(Gallery.tileDetail(for: tileItem("b.mp4"), sort: .oldest, locale: english, timeZone: gmt) == "MP4 · 21:53")
}

@Test func galleryTileDetailShowsTheSizeWhenSortedBySize() {
    let detail = Gallery.tileDetail(for: tileItem("c.gif"), sort: .size, locale: english, timeZone: gmt)
    #expect(detail.hasPrefix("GIF · 2"))
    #expect(detail.hasSuffix("MB"))
}

@Test func galleryTileDetailShowsTheDateWhenSortedByName() {
    #expect(Gallery.tileDetail(for: tileItem("d.png"), sort: .name, locale: english, timeZone: gmt) == "PNG · 10 Nov 2026")
}
