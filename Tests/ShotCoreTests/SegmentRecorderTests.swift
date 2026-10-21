import Foundation
import Synchronization
import Testing
@testable import ShotCore

/// A clock the test moves by hand.
private final class HandClock: Sendable {
    let time = Mutex(0.0)

    func advance(_ seconds: Double) {
        time.withLock { $0 += seconds }
    }
}

/// Writes each segment's number to its file when it finishes, or fails when told to.
private final class TextSource: RecordingSource {
    let started = Mutex<[URL]>([])
    let failing = Mutex<ShotCommandError?>(nil)
    /// How long each segment turns out to be, in order, where it's known.
    let lengths = Mutex<[Double]>([])
    /// How much each segment has recorded when it starts.
    let offset: Double

    init(offset: Double = 0) {
        self.offset = offset
    }

    func start(to url: URL) async throws(ShotCommandError) -> any RecordingSegment {
        let number = started.withLock { urls in
            urls.append(url)
            return urls.count
        }
        return TextSegment(url: url, number: number, source: self)
    }
}

private struct TextSegment: RecordingSegment {
    let url: URL
    let number: Int
    let source: TextSource
    var offset: Double { source.offset }

    func finish() async throws(ShotCommandError) -> Double? {
        if let failure = source.failing.withLock({ $0 }) {
            throw failure
        }
        try? Data("\(number)".utf8).write(to: url)
        return source.lengths.withLock { $0.isEmpty ? nil : $0.removeFirst() }
    }

    func cancel() {}
}

/// Joins segments by writing their texts one after another.
private struct TextJoiner: VideoAssembler {
    func trim(_ input: URL, kept: [TrimRange], speed: Double, muted: Bool, to output: URL, as fileType: String?) async throws -> Bool {
        false
    }

    func concatenate(_ segments: [URL], audio: [VideoConcatenator.SegmentAudio], to output: URL, muting muted: CutList) async throws {
        let joined = try segments.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "+")
        try Data(joined.utf8).write(to: output)
    }
}

@Test func aSegmentRecorderStartsASegmentForEachResumeAndJoinsThemOnStop() async throws {
    let scratch = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let clock = HandClock()
    let source = TextSource()
    let recorder = try await SegmentRecorder(source: source, assembler: TextJoiner(), scratch: scratch) { clock.time.withLock { $0 } }
    clock.advance(1.5)
    #expect(await recorder.elapsed == 1.5)
    await recorder.pause()
    #expect(await recorder.phase == .paused)
    clock.advance(10)
    // A pause that's paused, or a resume that's recording, does nothing.
    await recorder.pause()
    try await recorder.resume()
    try await recorder.resume()
    #expect(await recorder.phase == .recording)
    clock.advance(2)
    #expect(await recorder.elapsed == 3.5)
    #expect(source.started.withLock { $0 }.count == 2)

    let output = scratch.appendingPathComponent("joined.mp4")
    #expect(try await recorder.stop(to: output) == 3.5)
    #expect(try String(contentsOf: output, encoding: .utf8) == "1+2")
    #expect(await recorder.phase == .ended)
    // The segments' folder is gone, so only the joined file is left.
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path) == ["joined.mp4"])
    await #expect(throws: ShotCommandError.internal("the recording has already stopped")) {
        try await recorder.stop(to: output)
    }
}

@Test func aSegmentRecorderCountsWhatItsSegmentsSayTheyHold() async throws {
    let scratch = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let clock = HandClock()
    let source = TextSource(offset: 0.25)
    source.lengths.withLock { $0 = [1.5, 1.25] }
    let recorder = try await SegmentRecorder(source: source, assembler: TextJoiner(), scratch: scratch) { clock.time.withLock { $0 } }
    clock.advance(1)
    #expect(await recorder.elapsed == 1.25)
    await recorder.pause()
    #expect(await recorder.elapsed == 1.5)
    try await recorder.resume()
    clock.advance(0.5)
    #expect(await recorder.elapsed == 2.25)
    #expect(try await recorder.stop(to: scratch.appendingPathComponent("joined.mp4")) == 2.75)
}

@Test func aSegmentRecorderMovesASingleSegmentIntoPlace() async throws {
    let scratch = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let recorder = try await SegmentRecorder(source: TextSource(), assembler: UnusedVideo(), scratch: scratch)
    let output = scratch.appendingPathComponent("one.mp4")
    _ = try await recorder.stop(to: output)
    #expect(try String(contentsOf: output, encoding: .utf8) == "1")
}

@Test func aSegmentRecorderSaysWhyASegmentFailedAndSavesNothing() async throws {
    let scratch = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let source = TextSource()
    let recorder = try await SegmentRecorder(source: source, assembler: TextJoiner(), scratch: scratch)
    source.failing.withLock { $0 = .io("the screen went away") }
    await recorder.pause()
    source.failing.withLock { $0 = nil }
    try await recorder.resume()
    let output = scratch.appendingPathComponent("failed.mp4")
    await #expect(throws: ShotCommandError.io("the screen went away")) {
        try await recorder.stop(to: output)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
}

@Test func aSegmentRecorderThrowsItsSegmentsAwayWhenDiscarded() async throws {
    let scratch = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: scratch) }
    let recorder = try await SegmentRecorder(source: TextSource(), assembler: UnusedVideo(), scratch: scratch)
    await recorder.discard()
    #expect(await recorder.phase == .ended)
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
}
