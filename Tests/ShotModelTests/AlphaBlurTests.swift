import Foundation
import Testing
@testable import ShotModel

// Below about 0.8 the narrowest box, 3 wide, is already too wide, so the blur is none.
@Test(arguments: [1, 2, 4, 7.5, 16])
func threeBoxesHaveAboutTheVarianceOfTheGaussian(sigma: Double) {
    let widths = AlphaBlur.boxWidths(sigma: sigma)
    #expect(widths.count == 3 && widths.allSatisfy { $0 % 2 == 1 })
    // A box of width w has variance (w² - 1) / 12, and variances add.
    let variance = widths.reduce(0.0) { $0 + Double($1 * $1 - 1) / 12 }
    #expect(abs(variance.squareRoot() - sigma) < max(0.5, sigma * 0.1))
    #expect(AlphaBlur.reach(sigma: sigma) == widths.reduce(0) { $0 + ($1 - 1) / 2 })
}

@Test func noBlurLeavesTheLevelsAsTheyAre() {
    #expect(AlphaBlur.boxWidths(sigma: 0) == [1, 1, 1])
    var levels: [UInt8] = [0, 255, 0, 128]
    levels.withUnsafeMutableBufferPointer { AlphaBlur.blur($0, width: 4, height: 1, stride: 4, sigma: 0) }
    #expect(levels == [0, 255, 0, 128])
}

@Test func aBlurredDotSpreadsEvenlyAndKeepsItsWeight() {
    let side = 21, stride = 24
    var levels = [UInt8](repeating: 0, count: stride * side)
    // A 3 × 3 block in the middle, which keeps the spread levels above rounding.
    for y in 9...11 {
        for x in 9...11 {
            levels[y * stride + x] = 255
        }
    }
    levels.withUnsafeMutableBufferPointer { AlphaBlur.blur($0, width: side, height: side, stride: stride, sigma: 2) }
    func at(_ x: Int, _ y: Int) -> Int { Int(levels[y * stride + x]) }
    #expect(at(10, 10) < 255 && at(10, 10) > at(10, 12) && at(10, 12) > at(10, 14))
    // Each pass rounds, so mirrored levels can differ by 1.
    #expect(abs(at(7, 10) - at(13, 10)) <= 1 && abs(at(10, 7) - at(10, 13)) <= 1 && abs(at(7, 10) - at(10, 7)) <= 1)
    #expect(at(0, 0) == 0)
    // The padding past each row is left alone.
    #expect(levels[10 * stride + side] == 0)
    let total = (0..<side).reduce(0) { sum, y in sum + (0..<side).reduce(0) { $0 + at($1, y) } }
    #expect(abs(total - 9 * 255) < 9 * 255 / 20)
}

@Test func levelsPastTheEdgeCountAsClear() {
    var levels = [UInt8](repeating: 255, count: 16 * 16)
    levels.withUnsafeMutableBufferPointer { AlphaBlur.blur($0, width: 16, height: 16, stride: 16, sigma: 2) }
    #expect(levels[8 * 16] < 200 && levels[0] < levels[8 * 16])
    #expect(levels[8 * 16 + 8] == 255)
}
