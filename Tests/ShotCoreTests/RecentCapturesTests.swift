import Foundation
import Testing
@testable import ShotCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func item(_ name: String, minutesAgo: Double, kind: GalleryKind = .image) -> GalleryItem {
    GalleryItem(url: URL(fileURLWithPath: "/shots/\(name)"), kind: kind, date: now.addingTimeInterval(-minutesAgo * 60), bytes: 1)
}

@Test func recentCapturesAreTheNewestFourNewestFirst() {
    let folder = [
        item("Shot A.png", minutesAgo: 50),
        item("Shot B.png", minutesAgo: 40),
        item("Recording C.mp4", minutesAgo: 30, kind: .video),
        item("Shot D.gif", minutesAgo: 20, kind: .gif),
        item("Shot E.png", minutesAgo: 10),
    ]
    #expect(RecentCaptures.newest(folder).map(\.name) == ["Shot E.png", "Shot D.gif", "Recording C.mp4", "Shot B.png"])
    #expect(RecentCaptures.newest(Array(folder.prefix(2))).map(\.name) == ["Shot B.png", "Shot A.png"])
    #expect(RecentCaptures.newest([]).isEmpty)
}

@Test func recentCapturesShowAnEditedImageOnce() {
    let folder = [item("Shot A.png", minutesAgo: 30), item("Shot A (2).png", minutesAgo: 5), item("Shot B.png", minutesAgo: 10)]
    #expect(RecentCaptures.newest(folder).map(\.name) == ["Shot A (2).png", "Shot B.png"])
}

@Test func galleryLatestWithALimitStartsWithLatest() {
    let folder = [item("Shot A.png", minutesAgo: 30), item("Shot B.png", minutesAgo: 10), item("Shot C.png", minutesAgo: 20)]
    #expect(Gallery.latest(in: folder, limit: 2).map(\.name) == ["Shot B.png", "Shot C.png"])
    #expect(Gallery.latest(in: folder, limit: 1).first == Gallery.latest(in: folder))
}

@Test func recentCaptureBadges() {
    #expect(RecentCaptures.badge(for: item("Shot.png", minutesAgo: 1), duration: nil) == "PNG")
    #expect(RecentCaptures.badge(for: item("Shot.jpg", minutesAgo: 1), duration: nil) == "JPG")
    #expect(RecentCaptures.badge(for: item("Shot.gif", minutesAgo: 1, kind: .gif), duration: nil) == "GIF")
    #expect(RecentCaptures.badge(for: item("Recording.mp4", minutesAgo: 1, kind: .video), duration: 12.2) == "0:12")
    #expect(RecentCaptures.badge(for: item("Recording.mp4", minutesAgo: 1, kind: .video), duration: nil) == nil)
}
