import Foundation
import Testing
@testable import ShotCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func file(_ name: String, minutesAgo: Double) -> SegmentRecovery.File {
    SegmentRecovery.File(name: name, modified: now.addingTimeInterval(-minutesAgo * 60))
}

@Test func leftoverSegmentsAreRecoveredInRecordingOrder() {
    let plan = SegmentRecovery.plan([file("b.mp4", minutesAgo: 30), file("a.mp4", minutesAgo: 40), file("c.mp4", minutesAgo: 20)], now: now)
    #expect(plan.segments.map(\.video) == ["a.mp4", "b.mp4", "c.mp4"])
    #expect(plan.orphans.isEmpty)
}

@Test func recentFilesAreLeftAloneInCaseAnotherShotIsRecording() {
    let plan = SegmentRecovery.plan([file("a.mp4", minutesAgo: 5), file("a-system.mov", minutesAgo: 5), file("junk.txt", minutesAgo: 1)], now: now)
    #expect(plan.segments.isEmpty)
    #expect(plan.orphans.isEmpty)
}

@Test func aSegmentKeepsItsAudioFiles() {
    let plan = SegmentRecovery.plan([file("a.mp4", minutesAgo: 30), file("a-system.mov", minutesAgo: 30), file("a-microphone.mov", minutesAgo: 30)], now: now)
    #expect(plan.segments.first?.system == "a-system.mov")
    #expect(plan.segments.first?.microphone == "a-microphone.mov")
    #expect(plan.segments.first?.files == ["a.mp4", "a-system.mov", "a-microphone.mov"])
}

@Test func audioWithoutItsVideoAndUnknownFilesAreSwept() {
    let plan = SegmentRecovery.plan([file("x-system.mov", minutesAgo: 30), file("y-microphone.mov", minutesAgo: 30), file("notes.txt", minutesAgo: 30)], now: now)
    #expect(plan.segments.isEmpty)
    #expect(plan.orphans == ["notes.txt", "x-system.mov", "y-microphone.mov"])
}

@Test func audioIsJoinedOnlyWhenEverySegmentHasBothFiles() {
    let both = SegmentRecovery.plan([file("a.mp4", minutesAgo: 30), file("a-system.mov", minutesAgo: 30), file("a-microphone.mov", minutesAgo: 30)], now: now)
    #expect(SegmentRecovery.audio(of: both.segments)?.map(\.system) == ["a-system.mov"])
    let missing = SegmentRecovery.plan([file("a.mp4", minutesAgo: 30), file("a-system.mov", minutesAgo: 30), file("a-microphone.mov", minutesAgo: 30), file("b.mp4", minutesAgo: 20)], now: now)
    #expect(SegmentRecovery.audio(of: missing.segments) == nil)
    #expect(SegmentRecovery.audio(of: []) == nil)
}
