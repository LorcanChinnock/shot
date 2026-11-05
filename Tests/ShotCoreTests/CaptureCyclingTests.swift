import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

struct CaptureCyclingTests {
    @Test func aspectRatiosStepForwardAndWrap() {
        #expect(AspectRatio.free.next() == .square)
        #expect(AspectRatio.sixteenNine.next() == .free)
    }

    @Test func aspectRatiosStepBackwardAndWrap() {
        #expect(AspectRatio.square.next(backward: true) == .free)
        #expect(AspectRatio.free.next(backward: true) == .sixteenNine)
    }

    @Test func aspectRatioValuesAreLongOverShortAndFreeHasNone() {
        #expect(AspectRatio.free.value == nil)
        #expect(AspectRatio.square.value == 1)
        #expect(AspectRatio.sixteenNine.value == 16.0 / 9)
    }

    @Test func aspectRatioLabelsSwapSidesInPortrait() {
        #expect(AspectRatio.sixteenNine.label(portrait: true) == "9:16")
        #expect(AspectRatio.fourThree.label(portrait: false) == "4:3")
        #expect(AspectRatio.square.label(portrait: true) == "1:1")
    }

    @Test func captureTargetsStepBothWaysAndWrap() {
        #expect(CaptureTarget.area.next() == .window)
        #expect(CaptureTarget.screen.next() == .area)
        #expect(CaptureTarget.area.next(backward: true) == .screen)
    }

    @Test func captureDelayStartsOffAndWrapsBackToIt() {
        #expect(CaptureDelay.choices.first == 0)
        #expect(CaptureDelay.next(after: 0) == ScreenshotTimer.delays.first)
        #expect(CaptureDelay.next(after: CaptureDelay.choices.last!) == 0)
        #expect(CaptureDelay.next(after: 7) == ScreenshotTimer.delays.first)
    }

    @Test func captureDelayLabelsOffAndSeconds() {
        #expect(CaptureDelay.label(0) == "Off")
        #expect(CaptureDelay.label(5) == "5 s")
    }

    @Test func onlyDrawOnNeedsAStrokeAndOnlyFadeOutPlaysAtTheEnd() {
        #expect(AnimationPreset.allCases.filter(\.needsStroke) == [.drawOn])
        #expect(AnimationPreset.allCases.filter(\.playsAtEnd) == [.fadeOut])
        #expect(AnimationPreset.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test func imageMetadataDefaultsToNothingExtra() {
        #expect(ImageMetadata() == ImageMetadata(windowShadow: false, projectID: nil))
    }

    @Test func everyErrorSaysWhatWentWrong() {
        let errors: [any LocalizedError] = [
            MediaProbe.ProbeError.unreadable("a.mov"), MediaProbe.ProbeError.empty("a.mov"),
            VideoTrimmer.TrimError.unsupportedFileType, VideoTrimmer.TrimError.exportFailed, VideoTrimmer.TrimError.nothingLeft,
            VideoConcatenator.ConcatError.noSegments, VideoConcatenator.ConcatError.exportFailed,
            AudioFileWriter.WriteError.unsupportedFormat, AudioFileWriter.WriteError.cannotAddInput, AudioFileWriter.WriteError.cannotStart,
        ]
        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }
}
