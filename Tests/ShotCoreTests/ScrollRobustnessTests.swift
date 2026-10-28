import Foundation
import Testing

@testable import ShotCore

// Scrolling as it really is: text drawn at fractional offsets, steady scrolls, flicks that slow down, frames dropped when
// the machine is busy, scrolling back over what was seen, and parts of the window that stay put.

private let sim = ScrollSimulator()

/// Feeds frames of `simulator` scrolled to each offset, the first of which must be (0, 0), and finishes.
private func capture(_ offsets: [(Double, Double)], simulator: ScrollSimulator = sim) -> (stitcher: ScrollStitcher, outcomes: [ScrollStitcher.Outcome]) {
    var stitcher = ScrollStitcher(first: simulator.frame(x: offsets[0].0, y: offsets[0].1))
    let outcomes = offsets.dropFirst().map { stitcher.add(simulator.frame(x: $0.0, y: $0.1)) }
    stitcher.finish()
    return (stitcher, outcomes)
}

private func steps(from start: Double, by step: Double, count: Int) -> [Double] {
    (0..<count).map { start + step * Double($0) }
}

private func expectFollowed(_ stitcher: ScrollStitcher, simulator: ScrollSimulator = sim, reachedX: Double, reachedY: Double, sourceLocation: SourceLocation = #_sourceLocation) {
    let size = stitcher.size
    #expect(abs(size.width - (simulator.width + Int(reachedX.rounded()))) <= 2, "width \(size.width)", sourceLocation: sourceLocation)
    #expect(abs(size.height - (simulator.height + Int(reachedY.rounded()))) <= 2, "height \(size.height)", sourceLocation: sourceLocation)
    #expect(agreement(of: stitcher.result, with: simulator) > 0.97, "agreement \(agreement(of: stitcher.result, with: simulator))", sourceLocation: sourceLocation)
}

@Test func simulatedSteadyScrollDown() {
    let ys = steps(from: 0, by: 13.37, count: 20)
    let run = capture(ys.map { (0.0, $0) })
    expectFollowed(run.stitcher, reachedX: 0, reachedY: ys.last!)
}

@Test func simulatedSteadyScrollSideways() {
    let xs = steps(from: 0, by: 17.9, count: 20)
    let run = capture(xs.map { ($0, 0.0) })
    expectFollowed(run.stitcher, reachedX: xs.last!, reachedY: 0)
}

@Test func simulatedFlickThatSlowsDown() {
    var y = 0.0, speed = 90.0
    var ys = [0.0]
    while speed > 1.5 {
        y += speed
        ys.append(y)
        speed *= 0.8
    }
    let run = capture(ys.map { (0.0, $0) })
    expectFollowed(run.stitcher, reachedX: 0, reachedY: ys.last!)
}

@Test func simulatedScrollWithFramesDropped() {
    // Every third frame arrives, so the content moves three times as far between the ones that do.
    let ys = steps(from: 0, by: 41.3, count: 10)
    let run = capture(ys.map { (0.0, $0) })
    expectFollowed(run.stitcher, reachedX: 0, reachedY: ys.last!)
}

@Test func simulatedScrollBackOverWhatWasSeen() {
    let down = steps(from: 0, by: 17.3, count: 12)
    let back = steps(from: down.last!, by: -15.1, count: 8)
    let again = steps(from: back.last!, by: 19.7, count: 16)
    let ys = down + back.dropFirst() + again.dropFirst()
    let run = capture(ys.map { (0.0, $0) })
    expectFollowed(run.stitcher, reachedX: 0, reachedY: ys.max()!)
}

@Test func simulatedScrollAtAnAngle() {
    let offsets = (0..<18).map { (Double($0) * 11.9, Double($0) * 14.3) }
    let run = capture(offsets)
    // Corners the path never showed are empty, so only what was painted is compared.
    let last = offsets.last!
    #expect(abs(run.stitcher.size.width - (sim.width + Int(last.0.rounded()))) <= 2)
    #expect(abs(run.stitcher.size.height - (sim.height + Int(last.1.rounded()))) <= 2)
    #expect(agreement(of: run.stitcher.result, with: sim) > 0.97)
}

@Test func simulatedStickyHeaderFooterAndFirstColumn() {
    var spreadsheet = sim
    spreadsheet.header = 30
    spreadsheet.footer = 24
    spreadsheet.leftColumn = 60
    let down = steps(from: 0, by: 15.7, count: 10).map { (0.0, $0) }
    let right = steps(from: 0, by: 19.1, count: 10).dropFirst().map { ($0, down.last!.1) }
    let run = capture(down + right, simulator: spreadsheet)
    let last = (down + right).last!
    #expect(abs(run.stitcher.size.width - (spreadsheet.width + Int(last.0.rounded()))) <= 2)
    #expect(abs(run.stitcher.size.height - (spreadsheet.height + Int(last.1.rounded()))) <= 2)
}

@Test func simulatedFloatingButtonStaysOutOfTheImage() {
    var page = sim
    page.floating = CGRect(x: 250, y: 200, width: 70, height: 36)
    let ys = steps(from: 0, by: 14.9, count: 16)
    let run = capture(ys.map { (0, $0) }, simulator: page)
    var plain = sim
    plain.floating = nil
    // Where the button was in the first frame is painted from later frames, so the result matches the plain page.
    #expect(agreement(of: run.stitcher.result, with: plain) > 0.95)
}

@Test func simulatedJerkyScrollingThatSpeedsUpAndSlowsDown() {
    // Deterministic pseudo-random steps from a pixel or two to a third of the area.
    var seed: UInt64 = 7
    var y = 0.0
    var ys = [0.0]
    for _ in 0..<24 {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        y += 1.5 + Double((seed >> 33) % 98)
        ys.append(y)
    }
    let run = capture(ys.map { (0.0, $0) })
    expectFollowed(run.stitcher, reachedX: 0, reachedY: ys.last!)
}

@Test func simulatedPauseAndResume() {
    // The same frame again and again while the person stops, then on.
    let first = steps(from: 0, by: 16.4, count: 8)
    let resumed = steps(from: first.last!, by: 16.4, count: 8).dropFirst()
    let ys = first + Array(repeating: first.last!, count: 6) + resumed
    let run = capture(ys.map { (0.0, $0) })
    expectFollowed(run.stitcher, reachedX: 0, reachedY: ys.last!)
}

@Test func simulatedJumpTooBigToFollowThenBackAndOn() {
    // A jump of more than the area's height has nothing in common with the last frame. Scrolling back to where it was
    // and on carries on as if it never happened.
    let down = steps(from: 0, by: 20.3, count: 8)
    let jumped = [down.last! + 650, down.last! + 700, down.last! + 700]
    let back = steps(from: down.last!, by: 12.7, count: 10)
    let ys = down + jumped + back
    let run = capture(ys.map { (0.0, $0) })
    #expect(run.outcomes.contains(.tooFar))
    expectFollowed(run.stitcher, reachedX: 0, reachedY: back.last!)
}

@Test func simulatedDiagonalWithAPinnedHeaderAndFirstColumn() {
    var spreadsheet = sim
    spreadsheet.header = 30
    spreadsheet.leftColumn = 60
    let offsets = (0..<14).map { (Double($0) * 13.3, Double($0) * 9.7) }
    let run = capture(offsets, simulator: spreadsheet)
    let last = offsets.last!
    #expect(abs(run.stitcher.size.width - (spreadsheet.width + Int(last.0.rounded()))) <= 2)
    #expect(abs(run.stitcher.size.height - (spreadsheet.height + Int(last.1.rounded()))) <= 2)
}
