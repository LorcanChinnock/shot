import Foundation
import Testing
@testable import ShotModel

@Test func exportOptionsDefaultsAndChoices() {
    let options = VideoExportOptions()
    #expect(options.format == .mp4)
    #expect(options.gifFrameRate == 15)
    #expect(options.gifWidth == 720)
    #expect(!options.muted)
    #expect(options.speed == 1)
    #expect(VideoExportOptions.gifFrameRates == [10, 15, 24])
    #expect(VideoExportOptions.gifWidths == [480, 720, 1080, VideoExportOptions.originalWidth])
    #expect(VideoExportOptions.speeds == [1, 1.5, 2])
    #expect(VideoExportFormat.gif.fileExtension == "gif")
    #expect(VideoExportFormat.mp4.fileExtension == "mp4")
}

@Test func originalWidthHasNoCap() {
    var options = VideoExportOptions()
    #expect(options.gifMaxWidth == 720)
    options.gifWidth = VideoExportOptions.originalWidth
    #expect(options.gifMaxWidth == nil)
}

@Test func outputLengthFollowsSpeed() {
    var options = VideoExportOptions()
    let range = TrimRange(start: 2, end: 8, duration: 10)
    #expect(options.outputLength(of: range) == 6)
    options.speed = 1.5
    #expect(options.outputLength(of: range) == 4)
    options.speed = 2
    #expect(options.outputLength(of: range) == 3)
}
