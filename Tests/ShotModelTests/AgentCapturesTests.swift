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

@Test(arguments: [("X (2)", "X", 2), ("X (12)", "X", 12), ("X", "X", 1), ("X (1)", "X", 1), ("X (02)", "X", 2), ("X(2)", "X(2)", 1), ("(2)", "(2)", 1), ("X (a)", "X (a)", 1)])
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
    let utc = TimeZone(identifier: "UTC")!
    #expect(AgentCaptures.date(since: "2026-10-10", now: now, timeZone: utc) == Date(timeIntervalSince1970: 1_791_590_400))
    // A bare date or a time without a zone is local time.
    #expect(AgentCaptures.date(since: "2026-10-10", now: now, timeZone: TimeZone(secondsFromGMT: -7 * 3600)!) == Date(timeIntervalSince1970: 1_791_590_400 + 7 * 3600))
    #expect(AgentCaptures.date(since: "2026-10-10T14:03", now: now, timeZone: utc) == Date(timeIntervalSince1970: 1_791_640_980))
    #expect(AgentCaptures.date(since: "2026-10-10T14:03:12", now: now, timeZone: utc) == Date(timeIntervalSince1970: 1_791_640_992))
    #expect(AgentCaptures.date(since: "yesterday", now: now) == nil)
    #expect(AgentCaptures.date(since: "-5m", now: now) == nil)
}

@Test func aNameMatchesExactlyByPathOrLooselyByWords() {
    #expect(AgentCaptures.named("Shot A.png", in: folder)?.name == "Shot A.png")
    #expect(AgentCaptures.named("/shots/Shot A (2).png", in: folder)?.name == "Shot A (2).png")
    // Loose matches look among the captures `ranked` gives, so they find the version with the markup.
    #expect(AgentCaptures.named("shot a", in: folder)?.name == "Shot A (3).png")
    #expect(AgentCaptures.named("RECORDING", in: folder)?.name == "Recording C.mp4")
    #expect(AgentCaptures.named("nothing like it", in: folder) == nil)
    #expect(AgentCaptures.named("  ", in: folder) == nil)
}

@Test func aSecondCaptureInTheSameSecondIsntAVersion() {
    let quick = [entry("Shot E.png", minutesAgo: 3), entry("Shot E (2).png", minutesAgo: 3 - 1.0 / 60)]
    #expect(AgentCaptures.ranked(quick).map(\.name) == ["Shot E (2).png", "Shot E.png"])
}

@Test func theSameNameInAnotherFolderIsAnotherCapture() {
    let twoFolders = [
        AgentCaptures.Entry(url: URL(fileURLWithPath: "/shots/Shot F.png"), isVideo: false, date: now),
        AgentCaptures.Entry(url: URL(fileURLWithPath: "/tmp/Shot F (2).png"), isVideo: false, date: now.addingTimeInterval(60)),
    ]
    #expect(AgentCaptures.ranked(twoFolders).count == 2)
}

@Test func aLooseNameFavoursWordsThatSitTogether() {
    let shots = [
        entry("Shot 2026-10-10 at 14.03.12.png", minutesAgo: 60),
        entry("Shot 2026-10-14 at 09.03.55.png", minutesAgo: 1),
    ]
    #expect(AgentCaptures.named("shot 14.03", in: shots)?.name == "Shot 2026-10-10 at 14.03.12.png")
    #expect(AgentCaptures.named("...", in: shots) == nil)
}
