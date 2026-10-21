import Foundation
import Testing
@testable import ShotCore

/// Times 0, 0.25, 0.5… for `count` samples, as the extractor takes them at four a second.
private func times(_ count: Int) -> [Double] {
    (0 ..< count).map { Double($0) / 4 }
}

/// Small noise everywhere, like a cursor or a clock ticking, with `changes` at the given samples.
private func differences(_ count: Int, changes: [Int: Double] = [:]) -> [Double] {
    var result: [Double] = [0]
    for index in 1 ..< max(count, 1) {
        let noise: Double = index % 3 == 0 ? 0.002 : 0.001
        result.append(changes[index] ?? noise)
    }
    return Array(result.prefix(count))
}

@Test func differenceIsTheMeanChangeFromZeroToOne() {
    #expect(FramePicker.difference([0, 0], [0, 0]) == 0)
    #expect(FramePicker.difference([0, 255], [255, 0]) == 1)
    #expect(FramePicker.difference([0, 0, 0, 0], [255, 0, 0, 0]) == 0.25)
    #expect(FramePicker.difference([1, 2], [1]) == 1)
    #expect(FramePicker.difference([], []) == 0)
}

@Test func aStillRecordingGivesEvenlySpacedFrames() {
    let picked = FramePicker.pick(differences: differences(41), times: times(41), count: 5)
    #expect(picked == [0, 10, 20, 30, 40])
}

@Test func eachSharpChangeIsShownOnceItHasHappened() {
    // Scene changes landing at samples 8, 20 and 33.
    let picked = FramePicker.pick(differences: differences(41, changes: [8: 0.6, 20: 0.4, 33: 0.5]), times: times(41), count: 5)
    #expect(picked == [0, 9, 21, 34, 40])
}

@Test func aSlowTransitionIsOneChangeShownWhereItSettles() {
    // A fade over samples 10 to 15, then still.
    let fade = Dictionary(uniqueKeysWithValues: (10 ... 15).map { ($0, 0.08) })
    let picked = FramePicker.pick(differences: differences(41, changes: fade), times: times(41), count: 3)
    #expect(picked == [0, 16, 40])
}

@Test func moreChangesThanFramesKeepsTheBiggest() {
    let changes: [Int: Double] = [5: 0.1, 10: 0.9, 15: 0.2, 20: 0.8, 25: 0.3, 30: 0.7]
    let picked = FramePicker.pick(differences: differences(41, changes: changes), times: times(41), count: 5)
    #expect(picked == [0, 11, 21, 31, 40])
}

@Test func changesCloserThanTheSpacingCountAsOne() {
    // Two flickers a quarter of a second apart, then the screen settles.
    let picked = FramePicker.pick(differences: differences(41, changes: [10: 0.5, 12: 0.5]), times: times(41), count: 3, minSpacing: 1)
    #expect(picked == [0, 13, 40])
}

@Test func tinyRecordingsAndCountsStillGiveSomething() {
    #expect(FramePicker.pick(differences: [], times: [], count: 8) == [])
    #expect(FramePicker.pick(differences: [0], times: [0], count: 8) == [0])
    #expect(FramePicker.pick(differences: [0, 0.5], times: [0, 0.25], count: 8) == [0, 1])
    #expect(FramePicker.pick(differences: differences(41), times: times(41), count: 1) == [40])
    #expect(FramePicker.pick(differences: differences(41), times: times(41), count: 0) == [])
    #expect(FramePicker.pick(differences: differences(5), times: times(5), count: 12) == [0, 1, 2, 3, 4])
}
