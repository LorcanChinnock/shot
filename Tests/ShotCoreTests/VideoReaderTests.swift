import Foundation
import Synchronization
import Testing
@testable import ShotCore

/// A file that's whatever `media` says, with `samples` for its sound.
private struct FakeReader: VideoReader {
    var media: ImportedMedia?
    var rates = (video: 0.0, audio: 0.0)
    var syncTimes: [Double]?
    var samples: [[Float]] = []
    /// What every read throws instead, such as ffmpeg missing on Linux.
    var failure: ShotCommandError?

    func info(of url: URL) async throws -> ImportedMedia {
        if let failure {
            throw failure
        }
        guard let media else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return media
    }

    func bitRates(of url: URL) async throws -> (video: Double, audio: Double) {
        rates
    }

    func syncTimes(atOrBefore times: [Double], in url: URL) async throws -> [Double]? {
        syncTimes
    }

    func readFrames(of url: URL, at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws {}

    func frames(of project: Project, canvasType: any Canvas.Type) async throws -> any VideoFrames {
        throw CocoaError(.featureUnsupported)
    }

    func readMonoSamples(of url: URL, sampleRate: Double, _ body: ([Float]) throws -> Void) async throws {
        try samples.forEach(body)
    }
}

/// Keeps the sections it's asked to trim and the segments it's asked to join, and writes nothing.
private final class FakeAssembler: VideoAssembler {
    let trimmed = Mutex<[[TrimRange]]>([])
    let joined = Mutex<[[URL]]>([])

    func trim(_ input: URL, kept: [TrimRange], speed: Double, muted: Bool, to output: URL, as fileType: String?) async throws -> Bool {
        trimmed.withLock { $0.append(kept) }
        return true
    }

    func concatenate(_ segments: [URL], audio: [VideoConcatenator.SegmentAudio], to output: URL, muting muted: CutList) async throws {
        joined.withLock { $0.append(segments) }
    }
}

private let clip = URL(fileURLWithPath: "/nowhere/clip.mp4")

@Test func probingKeepsWhatTheReaderFinds() async throws {
    let found = ImportedMedia(source: clip, duration: 3, size: CGSize(width: 640, height: 360), hasAudio: true)
    let media = try await MediaProbe.probe(clip, reader: FakeReader(media: found))
    #expect(media == found)
}

@Test func probingRefusesAFileThatsEmptyOrUnreadable() async {
    let silent = ImportedMedia(source: clip, duration: 3, size: nil, hasAudio: false)
    let endless = ImportedMedia(source: clip, duration: .infinity, size: CGSize(width: 1, height: 1), hasAudio: false)
    for media in [silent, endless] {
        await #expect(throws: MediaProbe.ProbeError.self) { try await MediaProbe.probe(clip, reader: FakeReader(media: media)) }
    }
    await #expect(throws: MediaProbe.ProbeError.self) { try await MediaProbe.probe(clip, reader: FakeReader()) }
}

@Test func aReaderThatCantRunSaysWhyRatherThanThatTheFileIsUnreadable() async throws {
    let missing = ShotCommandError.unavailable("Shot can't find ffmpeg")
    let reader = FakeReader(failure: missing)
    await #expect(throws: missing) { try await MediaProbe.probe(clip, reader: reader) }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    try Data([0]).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    for command in [ShotCommand.info(path: file.path), .gif(ShotCommand.GIFOptions(input: file.path)), .frames(ShotCommand.FramesOptions(input: file.path))] {
        await #expect(throws: missing, "\(command.name)") {
            try await ShotCommands.run(command, codec: StandInCodec(), canvasType: UnusedCanvas.self, reader: reader, assembler: UnusedVideo(), writer: UnusedVideo())
        }
    }
    // Any other failure is the file's.
    await #expect(throws: ShotCommandError.data("\(file.lastPathComponent) isn't an image or video Shot can read")) {
        try await ShotCommands.run(.info(path: file.path), codec: StandInCodec(), canvasType: UnusedCanvas.self, reader: FakeReader(), assembler: UnusedVideo(), writer: UnusedVideo())
    }
    #expect(ShotCommandError.io("ffmpeg stopped").localizedDescription == "ffmpeg stopped")
}

@Test func trimmingHandsTheAssemblerOnlyWhatTheCutsKeep() async throws {
    let assembler = FakeAssembler()
    let range = TrimRange(start: 1, end: 6, duration: 10)
    try await VideoTrimmer.trim(clip, range: range, cuts: CutList([2..<3]), to: clip, assembler: assembler)
    let kept = assembler.trimmed.withLock { $0 }
    #expect(kept == [[TrimRange(start: 1, end: 2, duration: 10), TrimRange(start: 3, end: 6, duration: 10)]])

    await #expect(throws: VideoTrimmer.TrimError.nothingLeft) {
        try await VideoTrimmer.trim(clip, range: range, cuts: CutList([0..<10]), to: clip, assembler: assembler)
    }
    #expect(assembler.trimmed.withLock { $0.count } == 1)
}

@Test func theSizeEstimateCopiesVideoBackToEachSyncFrame() async throws {
    let range = TrimRange(start: 1, end: 6, duration: 10)
    let cuts = CutList([2..<3])
    // 1–2 s reaches back to 0.5 s and 3–6 s to 3 s: 4.5 s of video at 800 bits a second, and 4 s of audio at 80.
    let synced = FakeReader(rates: (video: 800, audio: 80), syncTimes: [0.5, 3])
    #expect(try await VideoTrimmer.estimatedSize(of: clip, range: range, cuts: cuts, reader: synced) == 490)
    // Without sync frames the video is as long as what's kept.
    let unsynced = FakeReader(rates: (video: 800, audio: 80))
    #expect(try await VideoTrimmer.estimatedSize(of: clip, range: range, cuts: cuts, reader: unsynced) == 440)
}

@Test func concatenatingMovesASingleSegmentAndJoinsSeveral() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let segments = ["a.mp4", "b.mp4"].map { folder.appendingPathComponent($0) }
    for segment in segments {
        try Data([1]).write(to: segment)
    }
    let assembler = FakeAssembler()

    let single = folder.appendingPathComponent("single.mp4")
    try await VideoConcatenator.concatenate([segments[0]], to: single, assembler: assembler)
    #expect(FileManager.default.fileExists(atPath: single.path))
    #expect(assembler.joined.withLock { $0.isEmpty })

    try Data([1]).write(to: segments[0])
    try await VideoConcatenator.concatenate(segments, to: folder.appendingPathComponent("joined.mp4"), assembler: assembler)
    #expect(assembler.joined.withLock { $0 } == [segments])
    // The joined segments are deleted.
    #expect(!FileManager.default.fileExists(atPath: segments[1].path))

    await #expect(throws: VideoConcatenator.ConcatError.noSegments) {
        try await VideoConcatenator.concatenate([], to: single, assembler: assembler)
    }
}

@Test func aWaveformReducesTheReadersSamples() async throws {
    let media = ImportedMedia(source: clip, duration: 0.02, size: nil, hasAudio: true)
    // 8000 samples a second makes 80 samples a peak.
    let first = [Float](repeating: 0.5, count: 80)
    let second = [Float](repeating: -0.25, count: 80)
    let waveform = try #require(try await Waveform.load(clip, reader: FakeReader(media: media, samples: [first, second])))
    #expect(waveform.peaks == [WaveformPeak(min: 0, max: 0.5), WaveformPeak(min: -0.25, max: 0)])
    #expect(waveform.duration == 0.02)

    let mute = ImportedMedia(source: clip, duration: 1, size: CGSize(width: 1, height: 1), hasAudio: false)
    #expect(try await Waveform.load(clip, reader: FakeReader(media: mute)) == nil)
}
