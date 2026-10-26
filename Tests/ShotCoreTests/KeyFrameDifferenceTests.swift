import Testing
@testable import ShotCore

@Test func differenceIsTheMeanChangeFromZeroToOne() {
    #expect(KeyFrameExtractor.difference([0, 0], [0, 0]) == 0)
    #expect(KeyFrameExtractor.difference([0, 255], [255, 0]) == 1)
    #expect(KeyFrameExtractor.difference([0, 0, 0, 0], [255, 0, 0, 0]) == 0.25)
    #expect(KeyFrameExtractor.difference([1, 2], [1]) == 1)
    #expect(KeyFrameExtractor.difference([], []) == 0)
}
