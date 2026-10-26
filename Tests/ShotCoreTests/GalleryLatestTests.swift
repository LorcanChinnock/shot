import Foundation
import Testing
@testable import ShotCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func item(_ name: String, minutesAgo: Double, kind: GalleryKind = .image, folder: String = "/shots") -> GalleryItem {
    GalleryItem(url: URL(fileURLWithPath: "\(folder)/\(name)"), kind: kind, date: now.addingTimeInterval(-minutesAgo * 60), bytes: 1)
}

@Test func galleryLatestIsTheNewestCaptureNotTheNewestFile() {
    let folder = [
        item("Shot A.png", minutesAgo: 30),
        item("Shot A (2).png", minutesAgo: 20),
        item("Shot B.png", minutesAgo: 10),
        item("Recording C.mp4", minutesAgo: 5, kind: .video),
    ]
    #expect(Gallery.latest(in: folder)?.name == "Recording C.mp4")
    #expect(Gallery.latest(in: Array(folder.dropLast()))?.name == "Shot B.png")
    #expect(Gallery.latest(in: []) == nil)
}

@Test func galleryLatestPrefersAnImagesNewestVersion() {
    // Version 3 has the markup, even though version 2 was saved later, and the group is dated by its newest file.
    let versions = [item("Shot A.png", minutesAgo: 30), item("Shot A (2).png", minutesAgo: 1), item("Shot A (3).png", minutesAgo: 20)]
    #expect(Gallery.latest(in: versions)?.name == "Shot A (3).png")
    #expect(Gallery.latest(in: versions + [item("Shot B.png", minutesAgo: 10)])?.name == "Shot A (3).png")
}

@Test func galleryLatestNeverFoldsRecordingsIntoVersions() {
    let recordings = [item("Recording C.mp4", minutesAgo: 40, kind: .video), item("Recording C (2).mp4", minutesAgo: 5, kind: .video)]
    #expect(Gallery.latest(in: recordings)?.name == "Recording C (2).mp4")
}

@Test func galleryLatestCountsASameSecondCaptureAsSeparate() {
    let quick = [item("Shot E.png", minutesAgo: 3), item("Shot E (2).png", minutesAgo: 3 - 1.0 / 60)]
    #expect(Gallery.latest(in: quick)?.name == "Shot E (2).png")
    let newerOriginal = [item("Shot E.png", minutesAgo: 1), item("Shot E (2).png", minutesAgo: 1 + 1.0 / 60)]
    #expect(Gallery.latest(in: newerOriginal)?.name == "Shot E.png")
}

@Test func galleryLatestKeepsFoldersApart() {
    let twoFolders = [item("Shot F.png", minutesAgo: 5), item("Shot F (2).png", minutesAgo: 1, folder: "/tmp")]
    #expect(Gallery.latest(in: twoFolders)?.url.path == "/tmp/Shot F (2).png")
}

@Test(arguments: [("X (2)", "X", 2), ("X (12)", "X", 12), ("X", "X", 1), ("X (1)", "X", 1), ("X (02)", "X", 2), ("X(2)", "X(2)", 1), ("(2)", "(2)", 1), ("X (a)", "X (a)", 1)])
func galleryVersionSuffixesAreReadOnlyWhenTheyLookLikeOne(_ stem: String, _ base: String, _ version: Int) {
    #expect(Gallery.versioned(stem) == (base, version))
}
