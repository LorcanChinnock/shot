import Foundation
import Testing
@testable import ShotModel

private let then = Date(timeIntervalSinceReferenceDate: 800_000_000.123456)

private func file(_ name: String, bytes: Int = 100, minutes: Double = 0, folder: String = "/shots") -> TextIndex.File {
    TextIndex.File(path: "\(folder)/\(name)", bytes: bytes, modified: then.addingTimeInterval(minutes * 60))
}

@Test func anEntryCountsOnlyWhileItsFileIsUnchanged() {
    var index = TextIndex()
    index.set("Invoice 42", for: file("a.png"))
    #expect(index.text(of: file("a.png")) == "Invoice 42")
    #expect(index.text(of: file("a.png", bytes: 101)) == nil)
    #expect(index.text(of: file("a.png", minutes: 1)) == nil)
    #expect(index.text(of: file("b.png")) == nil)
}

@Test func theIndexReadsBackExactlyAndAnotherVersionStartsAfresh() throws {
    var index = TextIndex()
    index.set("Ça marche", for: file("a.png"))
    let read = TextIndex.decoded(try index.encoded())
    #expect(read == index)
    #expect(read.text(of: file("a.png")) == "Ça marche")
    var old = index
    old.version = TextIndex.currentVersion + 1
    #expect(TextIndex.decoded(try old.encoded()) == TextIndex())
    #expect(TextIndex.decoded(Data("not json".utf8)) == TextIndex())
    #expect(TextIndex.decoded(nil) == TextIndex())
}

@Test func reconcilingListsWhatsUnreadNewestFirst() {
    var index = TextIndex()
    index.set("read", for: file("a.png", minutes: 0))
    let unread = index.reconcile(folder: "/shots", files: [file("a.png"), file("b.png", minutes: 1), file("c.png", minutes: 2), file("a2.png", bytes: 7, minutes: 2)])
    #expect(unread.map(\.path) == ["/shots/a2.png", "/shots/c.png", "/shots/b.png"])
}

@Test func reconcilingDropsGoneFilesButKeepsOtherFolders() {
    var index = TextIndex()
    index.set("gone", for: file("gone.png"))
    index.set("elsewhere", for: file("x.png", folder: "/other"))
    index.set("nested", for: file("x.png", folder: "/shots/inner"))
    _ = index.reconcile(folder: "/shots/", files: [])
    #expect(index.entries.keys.sorted() == ["/other/x.png", "/shots/inner/x.png"])
}

@Test func aRenamedFileKeepsItsTextWithoutBeingReadAgain() {
    var index = TextIndex()
    index.set("Quarterly report", for: file("Shot 1.png", bytes: 555, minutes: 3))
    let unread = index.reconcile(folder: "/shots", files: [file("Report.png", bytes: 555, minutes: 3), file("New.png")])
    #expect(unread.map(\.path) == ["/shots/New.png"])
    #expect(index.text(of: file("Report.png", bytes: 555, minutes: 3)) == "Quarterly report")
    #expect(index.entries["/shots/Shot 1.png"] == nil)
}

@Test func foldedTextIsOnlyForFilesReadAsTheyAreNow() {
    var index = TextIndex()
    index.set("Café MENU", for: file("a.png"))
    index.set("", for: file("blank.png"))
    index.set("old", for: file("changed.png"))
    let folded = index.folded([file("a.png"), file("blank.png"), file("changed.png", bytes: 1), file("new.png")])
    #expect(folded == ["/shots/a.png": "cafe menu"])
}

@Test func searchIgnoresCaseAndAccentsAndABlankQueryMatchesNothing() {
    #expect(TextSearch.query("  CAFÉ ") == "cafe")
    #expect(TextSearch.query(" \n ") == nil)
    #expect(TextSearch.lines(in: "Total\nCafé crème\nCAFE NOIR", matching: "cafe") == ["Café crème", "CAFE NOIR"])
    #expect(TextSearch.lines(in: "Total", matching: "") == [])
}

@Test func onlyScreenshotsAreRead() {
    let date = Date()
    #expect(TextIndex.reads(AgentCaptures.Entry(url: URL(fileURLWithPath: "/shots/a.PNG"), isVideo: false, date: date)))
    #expect(!TextIndex.reads(AgentCaptures.Entry(url: URL(fileURLWithPath: "/shots/a.gif"), isVideo: false, date: date)))
    #expect(!TextIndex.reads(AgentCaptures.Entry(url: URL(fileURLWithPath: "/shots/a.mov"), isVideo: true, date: date)))
}

@Test func searchableTextMatchesByItsBytes() {
    let text = TextSearch.searchable("Résumé\nTOTAL: 42 €\n日本語のテキスト")
    for (query, found) in [("resume", true), ("total: 42 €", true), ("テキスト", true), ("42 $", false), ("résumés", false)] {
        #expect(TextSearch.contains(text, TextSearch.query(query) ?? "") == found, "\(query)")
    }
    #expect(TextSearch.contains(text, ""))
    #expect(!TextSearch.contains("", "a"))
}
