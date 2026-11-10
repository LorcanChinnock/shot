import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let gmt = TimeZone(identifier: "GMT")!
private let english = Locale(identifier: "en_GB")

private func previewItem(_ path: String, bytes: Int = 214_000) -> GalleryItem {
    let kind = GalleryKind(fileExtension: (path as NSString).pathExtension)!
    return GalleryItem(url: URL(fileURLWithPath: "/shots/\(path)"), kind: kind, date: Date(timeIntervalSince1970: 1_794_347_580), bytes: bytes)
}

@Test func galleryVersionsCountTheEditsBesideTheOriginal() {
    let items = ["a.png", "a (2).png", "a (3).png", "b.png", "Bugs/a (4).png"].map { previewItem($0) }
    #expect(Gallery.versions(of: items[0], in: items) == GalleryVersions(hasOriginal: true, edits: 2))
    #expect(Gallery.versions(of: items[2], in: items) == GalleryVersions(hasOriginal: true, edits: 2))
}

@Test func galleryVersionsAreNilForACaptureWithNone() {
    let items = ["a.png", "b.png", "a.mp4"].map { previewItem($0) }
    #expect(Gallery.versions(of: items[0], in: items) == nil)
    #expect(Gallery.versions(of: items[2], in: items) == nil)
}

@Test func galleryVersionsCountEditsWhoseOriginalHasGone() {
    let items = ["a (2).png", "a (3).png"].map { previewItem($0) }
    #expect(Gallery.versions(of: items[0], in: items) == GalleryVersions(hasOriginal: false, edits: 2))
}

@Test func gallerySizeLabelGivesPixelsAndBytes() {
    let label = Gallery.sizeLabel(pixels: CGSize(width: 1040, height: 600), bytes: 214_000, locale: english)
    #expect(label.hasPrefix("1,040 × 600 · 214"))
    #expect(label.lowercased().hasSuffix("kb"))
    #expect(!Gallery.sizeLabel(pixels: nil, bytes: 214_000, locale: english).contains("×"))
}

@Test func galleryFolderLabelStartsAtTheSaveFolder() {
    #expect(Gallery.folderLabel("", rootName: "Shot") == "Shot")
    #expect(Gallery.folderLabel("Clients/Acme", rootName: "Shot") == "Shot › Clients › Acme")
}

@Test func galleryTakenLabelSaysTodayForToday() {
    let label = Gallery.takenLabel(Date(), locale: english, timeZone: gmt)
    #expect(label.hasPrefix("Today"))
    let older = Gallery.takenLabel(Date(timeIntervalSince1970: 1_700_000_000), locale: english, timeZone: gmt)
    #expect(older.contains("2023"))
    #expect(older.contains("22:13"))
}

@Test func galleryStepStopsAtEitherEnd() {
    #expect(Gallery.stepped(from: 2, by: 1, count: 248) == 3)
    #expect(Gallery.stepped(from: 0, by: -1, count: 248) == nil)
    #expect(Gallery.stepped(from: 247, by: 1, count: 248) == nil)
}

@Test func textSearchRangesIgnoreCaseAndAccents() {
    let text = "Discount SPRING20 · spring20 again · Café"
    let ranges = TextSearch.ranges(of: "spring20", in: text)
    #expect(ranges.map { String(text[$0]) } == ["SPRING20", "spring20"])
    #expect(TextSearch.ranges(of: "cafe", in: text).map { String(text[$0]) } == ["Café"])
    #expect(TextSearch.ranges(of: "  ", in: text).isEmpty)
}

@Test func captureTextBoxesSurroundTheWordsAMatchTouches() {
    let words = [
        CaptureText.Word(text: "Discount", box: CGRect(x: 10, y: 20, width: 60, height: 12)),
        CaptureText.Word(text: "SPRING20", box: CGRect(x: 76, y: 20, width: 64, height: 12)),
        CaptureText.Word(text: "−$0.00", box: CGRect(x: 200, y: 20, width: 40, height: 12)),
    ]
    let line = CaptureText.Line(text: "Discount SPRING20 −$0.00", box: CGRect(x: 10, y: 20, width: 230, height: 12), words: words)
    let other = CaptureText.Line(text: "Total", box: CGRect(x: 10, y: 40, width: 40, height: 12))
    let text = CaptureText(width: 300, height: 100, lines: [line, other])
    #expect(text.boxes(matching: "spring") == [words[1].box])
    #expect(text.boxes(matching: "discount spring20") == [words[0].box.union(words[1].box)])
    #expect(text.boxes(matching: "total") == [other.box])
    #expect(text.boxes(matching: "missing").isEmpty)
}
