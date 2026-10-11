import Foundation
import Testing
@testable import ShotModel

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func entry(_ name: String, minutesAgo: Double, video: Bool = false) -> AgentCaptures.Entry {
    AgentCaptures.Entry(url: URL(fileURLWithPath: "/shots/\(name)"), isVideo: video, date: now.addingTimeInterval(-minutesAgo * 60))
}

private let folder = [
    entry("Shot A.png", minutesAgo: 30),
    entry("Shot A (2).png", minutesAgo: 20),
    entry("Shot A (3).png", minutesAgo: 25),
    entry("Shot B.png", minutesAgo: 10),
    entry("Recording C.mp4", minutesAgo: 5, video: true),
    entry("Recording C (2).mp4", minutesAgo: 40, video: true),
]

@Test func theLatestImageIsTheNewestCaptureNotTheNewestFile() {
    #expect(AgentCaptures.latest(folder, kind: .image)?.name == "Shot B.png")
    #expect(AgentCaptures.latest(folder, kind: .video)?.name == "Recording C.mp4")
    #expect(AgentCaptures.latest(folder, kind: .any)?.name == "Recording C.mp4")
    #expect(AgentCaptures.latest([], kind: .any) == nil)
}

@Test func anImagesNewestVersionStandsInForItsOriginal() {
    let names = AgentCaptures.ranked(folder, kind: .image).map(\.name)
    // Version 3 has the markup, even though version 2 was saved later; the group is dated by its newest file.
    #expect(names == ["Shot B.png", "Shot A (3).png"])
    #expect(AgentCaptures.ranked(folder, kind: .image).last?.date == now.addingTimeInterval(-20 * 60))
}

@Test func recordingsAreNeverFoldedIntoVersions() {
    #expect(AgentCaptures.ranked(folder, kind: .video).map(\.name) == ["Recording C.mp4", "Recording C (2).mp4"])
}

@Test func differentFormatsOfTheSameNameStayApart() {
    let both = [entry("Shot D.png", minutesAgo: 2), entry("Shot D (2).jpg", minutesAgo: 1)]
    #expect(AgentCaptures.ranked(both).count == 2)
}

@Test(arguments: [("X (2)", "X", 2), ("X (12)", "X", 12), ("X", "X", 1), ("X (1)", "X (1)", 1), ("X(2)", "X(2)", 1), ("(2)", "(2)", 1), ("X (a)", "X (a)", 1)])
func versionSuffixesAreReadOnlyWhenTheyLookLikeOne(_ stem: String, _ base: String, _ version: Int) {
    #expect(AgentCaptures.versioned(stem) == (base, version))
}

@Test(arguments: [(String?("image"), AgentCaptures.Kind.image), (" VIDEO ", .video), ("any", .any), ("screenshot", .any), (nil, .any)])
func kindIsLenient(_ text: String?, _ kind: AgentCaptures.Kind) {
    #expect(AgentCaptures.Kind(lenient: text) == kind)
}

@Test func listingIsClampedAndCanStartFromADate() {
    #expect(AgentCaptures.list(folder, limit: nil, since: nil).count == 4)
    #expect(AgentCaptures.list(folder, limit: 0, since: nil).count == 1)
    #expect(AgentCaptures.list(folder, limit: 1000, since: nil).count == 4)
    let lastQuarterHour = AgentCaptures.date(since: "15m", now: now)
    #expect(AgentCaptures.list(folder, limit: nil, since: lastQuarterHour).map(\.name) == ["Recording C.mp4", "Shot B.png"])
}

@Test func sinceReadsSpansAndISODates() {
    #expect(AgentCaptures.date(since: "10m", now: now) == now.addingTimeInterval(-600))
    #expect(AgentCaptures.date(since: " 2H ", now: now) == now.addingTimeInterval(-7200))
    #expect(AgentCaptures.date(since: "1d", now: now) == now.addingTimeInterval(-86400))
    #expect(AgentCaptures.date(since: "2026-10-10T14:03:12Z", now: now) == Date(timeIntervalSince1970: 1_791_640_992))
    #expect(AgentCaptures.date(since: "2026-10-10", now: now) == Date(timeIntervalSince1970: 1_791_590_400))
    #expect(AgentCaptures.date(since: "yesterday", now: now) == nil)
    #expect(AgentCaptures.date(since: "-5m", now: now) == nil)
}

@Test func aNameMatchesExactlyByPathOrLooselyByWords() {
    #expect(AgentCaptures.named("Shot A.png", in: folder)?.name == "Shot A.png")
    #expect(AgentCaptures.named("/shots/Shot A (2).png", in: folder)?.name == "Shot A (2).png")
    // Loose matches take the newest file that has every word.
    #expect(AgentCaptures.named("shot a", in: folder)?.name == "Shot A (2).png")
    #expect(AgentCaptures.named("RECORDING", in: folder)?.name == "Recording C.mp4")
    #expect(AgentCaptures.named("nothing like it", in: folder) == nil)
    #expect(AgentCaptures.named("  ", in: folder) == nil)
}
