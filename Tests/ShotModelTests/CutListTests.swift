import Foundation
import Testing
@testable import ShotModel

// MARK: Cut list

@Test func noCutsKeepTheWholeTrim() {
    let range = TrimRange(start: 1, end: 9, duration: 10)
    #expect(CutList().isEmpty)
    #expect(CutList().kept(in: range) == [range])
    #expect(CutList().keptLength(in: range) == 8)
}

@Test func twoCutsLeaveThreeSections() {
    let range = TrimRange(duration: 10)
    let cuts = CutList([2..<3, 6..<7.5])
    #expect(cuts.kept(in: range) == [
        TrimRange(start: 0, end: 2, duration: 10),
        TrimRange(start: 3, end: 6, duration: 10),
        TrimRange(start: 7.5, end: 10, duration: 10),
    ])
    #expect(cuts.keptLength(in: range) == 7.5)
}

@Test func cutsOutsideTheTrimAreIgnoredAndOverlapsClipped() {
    let range = TrimRange(start: 2, end: 8, duration: 10)
    let cuts = CutList([0..<1, 1.5..<3, 7..<9.5])
    #expect(cuts.kept(in: range) == [TrimRange(start: 3, end: 7, duration: 10)])
    #expect(cuts.keptLength(in: range) == 4)
    // A cut reaching the in or out point leaves nothing before or after it.
    #expect(CutList([2..<4]).kept(in: range) == [TrimRange(start: 4, end: 8, duration: 10)])
    #expect(CutList([5..<8]).kept(in: range) == [TrimRange(start: 2, end: 5, duration: 10)])
}

@Test func addingSortsAndMergesOverlappingOrTouchingCuts() {
    var cuts = CutList()
    cuts = cuts.adding(6..<7)
    cuts = cuts.adding(2..<3)
    #expect(cuts.cuts == [2..<3, 6..<7])
    #expect(cuts.adding(2.5..<6.5).cuts == [2..<7])
    #expect(cuts.adding(3..<4).cuts == [2..<4, 6..<7])
    #expect(cuts.adding(1..<8).cuts == [1..<8])
    #expect(cuts.adding(4..<4) == cuts)
}

@Test func cuttingASelectionKeepsItInsideTheTrim() {
    let range = TrimRange(start: 2, end: 8, duration: 10)
    #expect(CutList().cutting(1..<3, from: range)?.cuts == [2..<3])
    #expect(CutList().cutting(4..<5, from: range)?.cuts == [4..<5])
    // A selection wholly outside the trim changes nothing.
    #expect(CutList().cutting(8.5..<9.5, from: range) == CutList())
}

@Test func cuttingRefusesToLeaveLessThanTheMinimum() {
    let range = TrimRange(start: 2, end: 8, duration: 10)
    #expect(CutList().cutting(0..<10, from: range) == nil)
    #expect(CutList([2..<5]).cutting(5..<7.95, from: range) == nil)
    #expect(CutList([2..<5]).cutting(5..<7.9, from: range)?.cuts == [2..<7.9])
}

@Test func trimMustLeaveSomethingBetweenTheCuts() {
    let cuts = CutList([2..<8])
    #expect(cuts.allows(TrimRange(start: 1, end: 9, duration: 10)))
    #expect(cuts.allows(TrimRange(start: 1.9, end: 8, duration: 10)))
    #expect(!cuts.allows(TrimRange(start: 2.5, end: 8, duration: 10)))
    #expect(!cuts.allows(TrimRange(start: 3, end: 7, duration: 10)))
}

@Test func cutContainingATime() {
    let cuts = CutList([2..<3, 6..<7])
    #expect(cuts.cut(containing: 2) == 2..<3)
    #expect(cuts.cut(containing: 6.5) == 6..<7)
    #expect(cuts.cut(containing: 3) == nil)
    #expect(cuts.cut(containing: 1) == nil)
}

@Test func playbackReachingACutFindsItEvenWhenItIsShort() {
    let cuts = CutList([2..<2.02, 6..<7])
    // The player reports a time at or just after the cut's start, or a hair before it.
    #expect(cuts.cut(reachedAt: 2.005) == 2..<2.02)
    #expect(cuts.cut(reachedAt: 5.99) == 6..<7)
    #expect(cuts.cut(reachedAt: 6.4) == 6..<7)
    // Already past it, or nowhere near one.
    #expect(cuts.cut(reachedAt: 2.03) == nil)
    #expect(cuts.cut(reachedAt: 4) == nil)
}

@Test func onlyCutsBeforeTheEndOfPlaybackAreSkipPoints() {
    let range = TrimRange(start: 1, end: 9, duration: 10)
    let cuts = CutList([0..<0.5, 3..<4, 7..<9.5])
    #expect(cuts.skipPoints(in: range) == [3])
}

@Test func outputTimeMapsBackToTheSource() {
    let range = TrimRange(start: 1, end: 10, duration: 10)
    let cuts = CutList([2..<3, 6..<7.5])
    // Kept: 1–2, 3–6, 7.5–10.
    #expect(cuts.sourceTime(at: 0, in: range) == 1)
    #expect(cuts.sourceTime(at: 0.5, in: range) == 1.5)
    #expect(cuts.sourceTime(at: 1, in: range) == 3)
    #expect(cuts.sourceTime(at: 3.5, in: range) == 5.5)
    #expect(cuts.sourceTime(at: 4, in: range) == 7.5)
    #expect(cuts.sourceTime(at: 5, in: range) == 8.5)
    #expect(cuts.sourceTime(at: 99, in: range) == 10)
    #expect(CutList().sourceTime(at: 2, in: range) == 3)
}

@Test func playbackSkipsCutsAndStopsAtTheLastSection() {
    let range = TrimRange(start: 1, end: 9, duration: 10)
    let cuts = CutList([3..<4, 7..<9])
    #expect(cuts.playbackEnd(in: range) == 7)
    #expect(CutList().playbackEnd(in: range) == 9)
    #expect(cuts.playbackStart(from: 2, in: range) == 2)
    // Inside a cut, play from where it ends.
    #expect(cuts.playbackStart(from: 3.5, in: range) == 4)
    // Outside the trim, or at the end of the last section, start over.
    #expect(cuts.playbackStart(from: 0.5, in: range) == 1)
    #expect(cuts.playbackStart(from: 7, in: range) == 1)
    #expect(cuts.playbackStart(from: 8, in: range) == 1)
    #expect(cuts.playbackStart(from: 6.995, in: range) == 1)
}
