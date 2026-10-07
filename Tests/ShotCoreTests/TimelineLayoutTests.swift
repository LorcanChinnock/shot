import AVFoundation
import Testing
@testable import ShotCore

@Test func snapsToTheNearestPointInReach() {
    #expect(Snapping.snap(5.04, to: [0, 5, 5.1, 9], within: 0.05) == 5)
    #expect(Snapping.snap(5.07, to: [0, 5, 5.1, 9], within: 0.05) == 5.1)
    #expect(Snapping.snap(7, to: [0, 5, 9], within: 0.5) == nil)
    #expect(Snapping.snap(1, to: [], within: 1) == nil)
}

@Test func zoomStaysInRangeAndStepsBothWays() {
    #expect(TimelineZoom.zoomed(1, bySteps: -3) == 1)
    #expect(TimelineZoom.zoomed(60, bySteps: 5) == 64)
    #expect(TimelineZoom.zoomed(1, bySteps: 2) == 2.25)
    #expect(abs(TimelineZoom.zoomed(TimelineZoom.zoomed(1, bySteps: 3), bySteps: -3) - 1) < 1e-9)
}

@Test func zoomingKeepsTheAnchorTimeUnderTheCursor() {
    // 10 s over 800 pt at 4× is 3200 pt wide; 5 s sits at 1600, so to stay at x 400 the view starts at 1200.
    #expect(TimelineZoom.offset(keeping: 5, atViewX: 400, duration: 10, zoom: 4, viewWidth: 800) == 1200)
    #expect(TimelineZoom.offset(keeping: 0.1, atViewX: 400, duration: 10, zoom: 4, viewWidth: 800) == 0)
    #expect(TimelineZoom.offset(keeping: 10, atViewX: 0, duration: 10, zoom: 4, viewWidth: 800) == 2400)
    #expect(TimelineZoom.offset(keeping: 1, atViewX: 0, duration: 0, zoom: 4, viewWidth: 800) == 0)
}

@Test func peaksTrackTheLoudestAndQuietestSamplesPerSlice() {
    // 1000 samples a second makes 10 samples a peak.
    let samples = (0..<30).map { Float($0 % 10 == 3 ? 0.5 : $0 % 10 == 7 ? -0.25 : 0.1) }
    let peaks = Waveform.peaks(of: samples, sampleRate: 1000)
    #expect(peaks == Array(repeating: WaveformPeak(min: -0.25, max: 0.5), count: 3))
}

@Test func aPartialLastSliceStillMakesAPeak() {
    #expect(Waveform.peaks(of: [Float](repeating: 0.2, count: 15), sampleRate: 1000).count == 2)
    #expect(Waveform.peaks(of: [Float](), sampleRate: 1000).isEmpty)
}

@Test func mergingPeaksKeepsTheExtremesOfEachSpan() {
    let peaks = [0.1, 0.9, 0.2, 0.3].map { WaveformPeak(min: -Float($0), max: Float($0)) }
    let waveform = Waveform(peaks: peaks, duration: 4)
    #expect(waveform.peaks(in: 0..<4, count: 2) == [WaveformPeak(min: -0.9, max: 0.9), WaveformPeak(min: -0.3, max: 0.3)])
    #expect(waveform.peaks(in: 1..<2, count: 1) == [WaveformPeak(min: -0.9, max: 0.9)])
    #expect(waveform.peaks(in: 0..<4, count: 4) == peaks)
    #expect(waveform.peaks(in: 2..<2, count: 3).isEmpty)
}

extension MediaTests {
    @Test func loadingARecordingReadsItsToneAsEvenPeaks() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeScreenRecording(to: url, seconds: 2, audio: true)
        let waveform = try #require(try await Waveform.load(url))
        #expect(abs(waveform.duration - 2) < 0.1)
        // 8000 / 32768 is about 0.24, and AAC lands within a few percent of it.
        let peaks = waveform.peaks(in: 0.2..<1.8, count: 8)
        #expect(peaks.allSatisfy { $0.max > 0.2 && $0.max < 0.3 && $0.min < -0.2 })
    }

    @Test func aRecordingWithoutAudioHasNoWaveform() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeScreenRecording(to: url, seconds: 1, audio: false)
        #expect(try await Waveform.load(url) == nil)
    }
}

@Test func rulerLabelsStayApartAsYouZoom() {
    #expect(TimelineRuler.interval(pointsPerSecond: 100) == 1)
    #expect(TimelineRuler.interval(pointsPerSecond: 10) == 10)
    #expect(TimelineRuler.interval(pointsPerSecond: 1000) == 0.1)
    #expect(TimelineRuler.interval(pointsPerSecond: 0.001) == 3600)
    #expect(TimelineRuler.interval(pointsPerSecond: 0) == 3600)
}

@Test func rulerTicksRunToTheEnd() {
    #expect(TimelineRuler.ticks(duration: 5, interval: 2) == [0, 2, 4])
    #expect(TimelineRuler.ticks(duration: 4, interval: 2) == [0, 2, 4])
    #expect(TimelineRuler.ticks(duration: 0, interval: 1).isEmpty)
}

@Test func rulerLabelsShowTenthsOnlyWhenTheyMatter() {
    #expect(TimelineRuler.label(65, interval: 5) == "1:05")
    #expect(TimelineRuler.label(1.5, interval: 0.5) == "0:01.5")
    #expect(TimelineRuler.label(0, interval: 10) == "0:00")
}

private func layoutProject() throws -> Project {
    let base = Project(source: URL(fileURLWithPath: "/tmp/a.mov"), duration: 10, canvasSize: CGSize(width: 640, height: 360), hasAudio: true)
    let picture = ImportedMedia(source: URL(fileURLWithPath: "/tmp/b.mov"), duration: 2, size: CGSize(width: 64, height: 36), hasAudio: true)
    let first = try #require(base.importing(picture, at: 0)).project
    return try #require(first.importing(picture, at: 4)).project
}

@Test func lanesStackPicturesAboveTheMainTrackAndSoundBelow() throws {
    let project = try layoutProject()
    // Tracks: 0 main, 1 its sound, 2 picture, 3 sound, 4 picture, 5 sound.
    let layout = LaneLayout(project, top: 22)
    #expect(layout.lanes.map(\.track) == [4, 2, 0, 1, 3, 5])
    #expect(layout.lanes.map(\.y) == [22, 66, 110, 170, 214, 258])
    #expect(layout.height == 298)
}

@Test func aLoneRecordingHasTheMainLaneAndItsSound() {
    let project = Project(source: URL(fileURLWithPath: "/tmp/a.mov"), duration: 10, canvasSize: CGSize(width: 640, height: 360), hasAudio: true)
    let layout = LaneLayout(project, top: 22)
    #expect(layout.lanes.map(\.track) == [0, 1])
    #expect(layout.height == 122)
}

@Test func lanesAreFoundByPositionAndTrack() throws {
    let layout = LaneLayout(try layoutProject(), top: 22)
    #expect(layout.lane(at: 100)?.track == 2)
    #expect(layout.lane(at: 65) == nil, "the gap between lanes")
    #expect(layout.lane(at: 5) == nil, "the ruler")
    #expect(layout.lane(ofTrack: 0)?.y == 110)
    #expect(layout.lane(ofTrack: 9) == nil)
}

extension MediaTests {
    @Test func probingAFileReadsItsDurationPictureAndSound() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeScreenRecording(to: url, seconds: 2, audio: true)
        let media = try await MediaProbe.probe(url)
        #expect(abs(media.duration - 2) < 0.1 && media.size == CGSize(width: 640, height: 400) && media.hasAudio)
    }

    @Test func probingARotatedFileReportsItsPlayingSize() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeSolidVideo(to: url, color: .red, size: CGSize(width: 320, height: 180), seconds: 1, rotated: true)
        let media = try await MediaProbe.probe(url)
        #expect(media.size == CGSize(width: 180, height: 320) && !media.hasAudio)
    }

    @Test func probingSomethingThatIsntMediaFails() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: MediaProbe.ProbeError.self) { try await MediaProbe.probe(url) }
    }
}

@Test func annotationLanesSitAboveEverything() throws {
    let base = try layoutProject()
    let annotated = base.adding(annotation: Annotation(kind: .line(from: .zero, to: CGPoint(x: 5, y: 5)), color: RGBA.presets[0], lineWidth: 2), at: 1).project
    let layout = LaneLayout(annotated, top: 22)
    #expect(layout.lanes.first?.track == 6)
    #expect(layout.lanes.first?.height == 28)
    #expect(layout.lanes.map(\.track) == [6, 4, 2, 0, 1, 3, 5])
    #expect(layout.lanes[1].y == 54)
}

@Test func lanesScrollRatherThanSqueezeThePreview() throws {
    let layout = LaneLayout(try layoutProject(), top: 22)
    #expect(layout.visibleHeight(available: 1000, minimum: 78) == layout.height, "room to spare")
    #expect(layout.visibleHeight(available: 150, minimum: 78) == 150)
    #expect(layout.visibleHeight(available: 20, minimum: 78) == 78, "the ruler and the main lane stay in view")
}

@Test func trimmedEndsShowTheWholeRecordingAroundWhatsKept() throws {
    let full = Project(source: URL(fileURLWithPath: "/tmp/recording.mov"), duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: true)
    #expect(full.trimmedLead == 0 && full.trimmedEnds(ofTrack: 0).isEmpty)
    let trimmed = try #require(full.trimmingMain(.start, toSource: 2)?.trimmingMain(.end, toSource: 9))
    #expect(trimmed.trimmedLead == 2)
    let ends = trimmed.trimmedEnds(ofTrack: 0)
    #expect(ends.map(\.start) == [-2, 7] && ends.map(\.sourceStart) == [0, 9] && ends.map(\.sourceEnd) == [2, 10])
    #expect(trimmed.trimmedEnds(ofTrack: 1).map(\.start) == [-2, 7])
}

@Test func aCutInsideTheMainTrackIsMarkedNotDrawn() throws {
    let full = Project(source: URL(fileURLWithPath: "/tmp/recording.mov"), duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: false)
    let cut = try #require(full.deleting(range: 3..<5))
    #expect(cut.mainCuts == [3])
    #expect(cut.trimmedEnds(ofTrack: 0).isEmpty)
    let split = try #require(full.splitting(at: 4))
    #expect(split.mainCuts.isEmpty)
}

@Test func anImportedClipShowsWhatWasTrimmedOffBothEnds() throws {
    let music = ImportedMedia(source: URL(fileURLWithPath: "/tmp/music.m4a"), duration: 30, size: nil, hasAudio: true)
    let base = Project(source: URL(fileURLWithPath: "/tmp/recording.mov"), duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: false)
    let (imported, id) = try #require(base.importing(music, at: 4))
    let trimmed = try #require(imported.trimming(clip: id, .start, toTimeline: 6)?.trimming(clip: id, .end, toTimeline: 20))
    // 2 s off the front and 14 s off the back, drawn either side of the 6–20 s it plays.
    #expect(trimmed.trimmedEnds(ofTrack: 1).map(\.start) == [4, 20] && trimmed.trimmedEnds(ofTrack: 1).map(\.length) == [2, 14])
}
