import Foundation
import Testing
@testable import ShotCore

@Test func theChangedPixelsAreOneRectARunFromTheBottomLeft() {
    // 4 × 3, top row first: a run of two on the top row, two runs on the middle one, none on the bottom.
    let mask: [UInt8] = [
        0, 1, 1, 0,
        1, 0, 0, 1,
        0, 0, 0, 0,
    ]
    var expected = CanvasPath()
    expected.addRect(CGRect(x: 1, y: 2, width: 2, height: 1))
    expected.addRect(CGRect(x: 0, y: 1, width: 1, height: 1))
    expected.addRect(CGRect(x: 3, y: 1, width: 1, height: 1))
    #expect(ShotCommands.changedPixels(mask, width: 4, height: 3) == expected)
}

@Test func noChangedPixelsIsAnEmptyPath() {
    #expect(ShotCommands.changedPixels([UInt8](repeating: 0, count: 6), width: 3, height: 2).isEmpty)
}
