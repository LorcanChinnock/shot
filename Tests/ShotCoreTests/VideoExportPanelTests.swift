import Foundation
import Testing
@testable import ShotCore

@Test func exportPanelShowsGIFOptionsOnlyForAGIF() {
    #expect(VideoExportPanel.groups(for: .gif) == [.format, .frameRate, .width, .speed])
    #expect(VideoExportPanel.groups(for: .mp4) == [.format, .mute, .speed])
}

@Test func exportPanelLocksSpeedOnlyForADrawnMP4() {
    #expect(VideoExportPanel.speedIsLocked(format: .mp4, isComposite: true))
    #expect(!VideoExportPanel.speedIsLocked(format: .mp4, isComposite: false))
    #expect(!VideoExportPanel.speedIsLocked(format: .gif, isComposite: true))
    #expect(!VideoExportPanel.speedIsLocked(format: .gif, isComposite: false))
}

@Test func exportPanelLengthFollowsTheSpeed() {
    let fast = VideoExportOptions(format: .gif, speed: 2)
    #expect(VideoExportPanel.length(of: 9.3, options: fast, isComposite: false) == .init(seconds: 4.65, truncated: false))
    let mp4 = VideoExportOptions(format: .mp4, speed: 1.5)
    #expect(VideoExportPanel.length(of: 9, options: mp4, isComposite: false).seconds == 6)
}

@Test func exportPanelLengthIgnoresTheSpeedOfADrawnMP4() {
    // A drawn MP4 plays at its own speed, as `VideoExportPlan` writes it.
    let options = VideoExportOptions(format: .mp4, speed: 2)
    #expect(VideoExportPanel.length(of: 10, options: options, isComposite: true) == .init(seconds: 10, truncated: false))
}

@Test func exportPanelLengthStopsAGIFAtItsLongest() {
    let options = VideoExportOptions(format: .gif, speed: 1)
    #expect(VideoExportPanel.length(of: 90, options: options, isComposite: false) == .init(seconds: GIFExporter.maxDuration, truncated: true))
    // At 2× the same 90 seconds plays in 45, which fits.
    var fast = options
    fast.speed = 2
    #expect(VideoExportPanel.length(of: 90, options: fast, isComposite: false) == .init(seconds: 45, truncated: false))
    // An MP4 has no limit.
    #expect(VideoExportPanel.length(of: 90, options: VideoExportOptions(format: .mp4), isComposite: false).truncated == false)
}

@Test func exportPanelLabelsWidthsAndSpeeds() {
    #expect(VideoExportOptions.gifWidths.map(VideoExportPanel.widthLabel) == ["480", "720", "1080", "Full"])
    #expect(VideoExportOptions.speeds.map(VideoExportPanel.speedLabel) == ["1×", "1.5×", "2×"])
}
