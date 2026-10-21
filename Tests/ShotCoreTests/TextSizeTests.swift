import Foundation
import Testing
@testable import ShotCore

@Test func standardTextSizeKeepsEveryFontSize() {
    for size in [9.0, 11.5, 13, 28] {
        #expect(TextSize.standard.points(size) == size)
    }
}

@Test func largerTextSizesRoundToHalfPoints() {
    #expect(TextSize.large.points(13) == 15)
    #expect(TextSize.larger.points(13) == 17)
    #expect(TextSize.large.points(11.5) == 13)
    #expect(TextSize.larger.points(10) == 13)
}

@Test func eachTextSizeIsLargerThanTheOneBefore() {
    let sizes = TextSize.allCases.map { $0.points(12) }
    #expect(sizes == sizes.sorted())
    #expect(Set(sizes).count == sizes.count)
}
