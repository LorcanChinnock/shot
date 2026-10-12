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

@Test func originalNameDropsTheVersionSuffix() {
    let folder = URL(fileURLWithPath: "/tmp/shots")
    #expect(FileNaming.originalName(of: folder.appendingPathComponent("Shot 1 (2).png")) == "Shot 1.png")
    #expect(FileNaming.originalName(of: folder.appendingPathComponent("Shot 1 (12).jpg")) == "Shot 1.jpg")
    #expect(FileNaming.originalName(of: folder.appendingPathComponent("Shot 1.png")) == "Shot 1.png")
    // Only the trailing " (n)" is a version; brackets elsewhere are part of the name.
    #expect(FileNaming.originalName(of: folder.appendingPathComponent("Shot (draft).png")) == "Shot (draft).png")
}

@Test func nextVersionNeverReusesAnExistingName() {
    let folder = URL(fileURLWithPath: "/tmp/shots")
    let original = folder.appendingPathComponent("Shot 1.png")
    #expect(FileNaming.nextVersionURL(of: original) { _ in false }.lastPathComponent == "Shot 1 (2).png")
    let taken: Set<String> = ["Shot 1.png", "Shot 1 (2).png"]
    #expect(FileNaming.nextVersionURL(of: original) { taken.contains($0.lastPathComponent) }.lastPathComponent == "Shot 1 (3).png")
    let version = folder.appendingPathComponent("Shot 1 (2).png")
    #expect(FileNaming.nextVersionURL(of: version) { taken.contains($0.lastPathComponent) }.lastPathComponent == "Shot 1 (3).png")
}

@Test func aVersionSavedInAnotherFormatTakesThatFormatsExtension() {
    let folder = URL(fileURLWithPath: "/tmp/shots")
    let none: (URL) -> Bool = { _ in false }
    // Shot writes only PNG and JPEG, so a HEIC or TIFF saves as PNG and its version must say so.
    #expect(FileNaming.nextVersionURL(of: folder.appendingPathComponent("Photo.heic"), savedAs: .png, exists: none).lastPathComponent == "Photo (2).png")
    #expect(FileNaming.nextVersionURL(of: folder.appendingPathComponent("Scan (2).tiff"), savedAs: .png, exists: none).lastPathComponent == "Scan (2).png")
    // An extension that already names the format is kept as written.
    #expect(FileNaming.nextVersionURL(of: folder.appendingPathComponent("Photo.jpeg"), savedAs: .jpeg, exists: none).lastPathComponent == "Photo (2).jpeg")
    #expect(FileNaming.nextVersionURL(of: folder.appendingPathComponent("Photo.JPG"), savedAs: .jpeg, exists: none).lastPathComponent == "Photo (2).JPG")
    let taken: Set<String> = ["Photo (2).png"]
    #expect(FileNaming.nextVersionURL(of: folder.appendingPathComponent("Photo.heic"), savedAs: .png) { taken.contains($0.lastPathComponent) }.lastPathComponent == "Photo (3).png")
}
