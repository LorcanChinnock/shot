import Foundation
import Testing
@testable import ShotModel

private let saved = Date(timeIntervalSince1970: 1_791_640_992)

private let capture = ProjectFile(path: "/Users/me/Shots/Shot 1.png", volume: "VOL-A", number: 42, size: 1000, modified: saved)

private func entry(stamped: Bool = true, file: ProjectFile = capture, date: Date = saved) -> ProjectEntry {
    ProjectEntry(id: "ID-1", stamped: stamped, file: file, origin: ProjectOrigin(via: .app, date: date))
}

@Test func anMCPOriginEncodesTheClientToolAndSecond() throws {
    let origin = ProjectOrigin(via: .mcp, client: "claude-code", action: "annotate", date: Date(timeIntervalSince1970: 1_791_640_992.8))
    let text = try #require(String(data: ProjectEntry.encoder().encode(origin), encoding: .utf8))
    #expect(text == #"{"action":"annotate","client":"claude-code","date":"2026-10-10T14:03:12Z","via":"mcp"}"#)
}

@Test func anAppOriginLeavesClientAndActionOut() throws {
    let text = try #require(String(data: ProjectEntry.encoder().encode(ProjectOrigin(via: .app, date: saved)), encoding: .utf8))
    #expect(text == #"{"date":"2026-10-10T14:03:12Z","via":"app"}"#)
}

@Test(arguments: [ProjectOrigin.Via.app, .cli, .mcp])
func originsDecodeFromWhatTheyEncode(_ via: ProjectOrigin.Via) throws {
    let origin = ProjectOrigin(via: via, client: via == .mcp ? "cursor" : nil, action: via == .app ? nil : "trim", date: saved)
    #expect(try ProjectEntry.decoder().decode(ProjectOrigin.self, from: ProjectEntry.encoder().encode(origin)) == origin)
}

@Test func anEntryRoundTripsWithItsOriginal() throws {
    var project = entry()
    project.original = ProjectFile(path: "/Users/me/Shots/Shot.png", bookmark: Data([1, 2, 3]), volume: "VOL-A", number: 7)
    let data = try ProjectEntry.encoder().encode(project)
    #expect(try ProjectEntry.decoder().decode(ProjectEntry.self, from: data) == project)
    #expect(String(data: data, encoding: .utf8)?.contains(#""schema":"shot.project/1""#) == true)
}

@Test func pngJPEGAndVideosAreStampedAndGIFsArent() {
    #expect(["png", "JPG", "jpeg", "mp4", "MOV"].allSatisfy(ProjectKey.stamps(pathExtension:)))
    #expect(!ProjectKey.stamps(pathExtension: "gif"))
    #expect(!ProjectKey.stamps(pathExtension: ""))
}

@Test func aFileThatCantHoldAnIDIsKeyedByVolumeAndInode() {
    let id = ProjectKey.id(identifying: ProjectFile(path: "/a.gif", volume: "VOL-A", number: 42))
    #expect(id == "file-VOL-A-42")
    #expect(ProjectKey.isIdentity(id ?? ""))
    #expect(!ProjectKey.isIdentity(ProjectKey.newID()))
    #expect(ProjectKey.id(identifying: ProjectFile(path: "/a.gif", number: 42)) == nil)
}

@Test func storeFileNamesRoundTripAndCantLeaveTheFolder() {
    let id = ProjectKey.newID()
    #expect(ProjectKey.fileName(for: id).flatMap(ProjectKey.id(fromFileName:)) == id)
    #expect(ProjectKey.fileName(for: "../x") == nil)
    #expect(ProjectKey.fileName(for: "a/b") == nil)
    #expect(ProjectKey.fileName(for: "") == nil)
    #expect(ProjectKey.id(fromFileName: ".DS_Store") == nil)
    #expect(ProjectKey.id(fromFileName: "notes.txt") == nil)
}

@Test func aFileIsTheSameAfterAMoveOnItsVolume() {
    #expect(capture.matches(ProjectFile(path: "/Users/me/Elsewhere/Renamed.png", volume: "VOL-A", number: 42)))
    #expect(!capture.matches(ProjectFile(path: "/Volumes/B/Shot 1.png", volume: "VOL-B", number: 42)))
}

@Test func aFileRewrittenInPlaceIsTheSameWhenItsSizeAndDateAre() {
    #expect(capture.matches(ProjectFile(path: capture.path, volume: "VOL-A", number: 99, size: 1000, modified: saved.addingTimeInterval(0.4))))
    #expect(!capture.matches(ProjectFile(path: capture.path, volume: "VOL-A", number: 99, size: 1001, modified: saved)))
    #expect(!capture.matches(ProjectFile(path: capture.path, volume: "VOL-A", number: 99, size: 1000, modified: saved.addingTimeInterval(5))))
    #expect(!ProjectFile(path: "/a.gif").matches(ProjectFile(path: "/a.gif")))
}

@Test func aStampedEntryKnowsItsFileByTheIDAlone() {
    let elsewhere = ProjectFile(path: "/Users/me/Moved.png", volume: "VOL-B", number: 1)
    #expect(entry().isFile(ProjectSighting(file: elsewhere, stampedID: "ID-1")))
    #expect(!entry().isFile(ProjectSighting(file: capture, stampedID: "ID-2")))
    #expect(!entry().isFile(ProjectSighting(file: capture)))
}

@Test func anUnstampedEntryKnowsItsFileByIdentity() {
    let gif = entry(stamped: false)
    #expect(gif.isFile(ProjectSighting(file: ProjectFile(path: "/Users/me/New.gif", volume: "VOL-A", number: 42))))
    #expect(!gif.isFile(ProjectSighting(file: ProjectFile(path: capture.path, volume: "VOL-A", number: 43, size: 5))))
}

@Test func pruningKeepsAProjectWhoseFileIsFound() {
    let now = saved.addingTimeInterval(86400)
    #expect(ProjectPruning.keeps(entry(), sightings: [ProjectSighting(file: capture, stampedID: "ID-1")], volumeMounted: true, now: now))
}

@Test func pruningDropsAProjectWhoseFileIsGoneOrReplaced() {
    let now = saved.addingTimeInterval(86400)
    #expect(!ProjectPruning.keeps(entry(), sightings: [], volumeMounted: true, now: now))
    #expect(!ProjectPruning.keeps(entry(), sightings: [ProjectSighting(file: capture, stampedID: nil)], volumeMounted: true, now: now))
}

@Test func pruningKeepsAProjectOnADiskThatIsntMounted() {
    #expect(ProjectPruning.keeps(entry(), sightings: [], volumeMounted: false, now: saved.addingTimeInterval(86400)))
}

@Test func pruningSparesAProjectJustWritten() {
    #expect(ProjectPruning.keeps(entry(), sightings: [], volumeMounted: true, now: saved.addingTimeInterval(60)))
    #expect(!ProjectPruning.keeps(entry(), sightings: [], volumeMounted: true, now: saved.addingTimeInterval(ProjectPruning.grace)))
}
