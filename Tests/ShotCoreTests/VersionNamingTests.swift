import Foundation
import Testing
@testable import ShotCore

private let folder = URL(fileURLWithPath: "/tmp/shots")

@Test func originalNameDropsTheVersionSuffix() {
    #expect(VersionNaming.originalName(of: folder.appendingPathComponent("Shot 1 (2).png")) == "Shot 1.png")
    #expect(VersionNaming.originalName(of: folder.appendingPathComponent("Shot 1 (12).jpg")) == "Shot 1.jpg")
    #expect(VersionNaming.originalName(of: folder.appendingPathComponent("Shot 1.png")) == "Shot 1.png")
    // Only the trailing " (n)" is a version; brackets elsewhere are part of the name.
    #expect(VersionNaming.originalName(of: folder.appendingPathComponent("Shot (draft).png")) == "Shot (draft).png")
}

@Test func nextVersionNeverReusesAnExistingName() {
    let original = folder.appendingPathComponent("Shot 1.png")
    #expect(VersionNaming.nextVersionURL(of: original) { _ in false }.lastPathComponent == "Shot 1 (2).png")
    let taken: Set<String> = ["Shot 1.png", "Shot 1 (2).png"]
    #expect(VersionNaming.nextVersionURL(of: original) { taken.contains($0.lastPathComponent) }.lastPathComponent == "Shot 1 (3).png")
    let version = folder.appendingPathComponent("Shot 1 (2).png")
    #expect(VersionNaming.nextVersionURL(of: version) { taken.contains($0.lastPathComponent) }.lastPathComponent == "Shot 1 (3).png")
}

@Test func aFileWithNoExtensionGetsANextVersionWithNone() {
    let original = URL(fileURLWithPath: "/tmp/Notes")
    #expect(VersionNaming.nextVersionURL(of: original) { _ in false }.lastPathComponent == "Notes (2)")
}

@Test func aCommandWritesBesideItsInputAndTakesTheNextVersionOnlyWhenItMust() {
    let none: (URL) -> Bool = { _ in false }
    let png = folder.appendingPathComponent("Shot 1.png")
    // The same name would be the input itself, so it's a version.
    #expect(VersionNaming.commandOutputURL(for: png, pathExtension: "png", exists: none).lastPathComponent == "Shot 1 (2).png")
    // A new extension is a new name, unless a file already has it.
    let heic = folder.appendingPathComponent("Photo.heic")
    #expect(VersionNaming.commandOutputURL(for: heic, pathExtension: "png", exists: none).lastPathComponent == "Photo.png")
    let taken: Set<String> = ["Photo.png", "Photo (2).png"]
    #expect(VersionNaming.commandOutputURL(for: heic, pathExtension: "png") { taken.contains($0.lastPathComponent) }.lastPathComponent == "Photo (3).png")
}

@Test func aVideoCopyStaysAMOVOrBecomesAnMP4() {
    #expect(VersionNaming.videoCopyExtension(of: folder.appendingPathComponent("Clip.MOV")) == "mov")
    #expect(VersionNaming.videoCopyExtension(of: folder.appendingPathComponent("Clip.mp4")) == "mp4")
    #expect(VersionNaming.videoCopyExtension(of: folder.appendingPathComponent("Clip.m4v")) == "mp4")
}
