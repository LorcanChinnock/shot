import AVFoundation
import Synchronization
import Testing
@testable import ShotCore

private struct DecodeFailed: Error {}

@Test func aFrameThatDoesntDecodeRepeatsTheOneBeforeIt() {
    var fill = GIFFrameFill<Int>()

    #expect(fill.next(.success(1), delay: 0.1)?.image == 1)
    let standIn = fill.next(.failure(DecodeFailed()), delay: 0.07)
    #expect(standIn?.image == 1)
    #expect(standIn?.delay == 0.07)
    #expect(fill.next(.success(3), delay: 0.1)?.image == 3)

    #expect(fill.written == 3)
    #expect(fill.skipped == 1)
}

@Test func framesThatDontDecodeBeforeTheFirstGoodOneLengthenIt() {
    var fill = GIFFrameFill<Int>()

    #expect(fill.next(.failure(DecodeFailed()), delay: 0.1) == nil)
    #expect(fill.next(.failure(DecodeFailed()), delay: 0.07) == nil)
    let first = fill.next(.success(3), delay: 0.1)

    #expect(first?.image == 3)
    #expect(abs((first?.delay ?? 0) - 0.27) < 1e-9)
    #expect(fill.next(.success(4), delay: 0.1)?.delay == 0.1)
    #expect(fill.written == 2)
    #expect(fill.skipped == 2)
}

@Test func whenNoFrameDecodesNothingIsWrittenAndTheErrorIsKept() {
    var fill = GIFFrameFill<Int>()

    for _ in 0..<3 {
        #expect(fill.next(.failure(DecodeFailed()), delay: 0.1) == nil)
    }

    #expect(fill.written == 0)
    #expect(fill.lastError is DecodeFailed)
}

@Test func aStageReportsItsShareOfTheWhole() {
    let reported = Mutex<[Double]>([])
    let whole: @Sendable (Double) -> Void = { value in reported.withLock { $0.append(value) } }
    let audio = ExportProgress.stage(whole, from: 0.7, to: 0.85)

    for fraction in [-1, 0, 0.5, 1, 2.0] {
        audio(fraction)
    }

    let values = reported.withLock { $0 }
    #expect(zip(values, [0.7, 0.7, 0.775, 0.85, 0.85]).allSatisfy { abs($0 - $1) < 1e-9 })
}

@Test func anAVFoundationFailureSaysWhyAfterWhat() {
    let error = NSError(domain: AVFoundationErrorDomain, code: AVError.decodeFailed.rawValue, userInfo: [
        NSLocalizedDescriptionKey: "Cannot Decode",
        NSLocalizedFailureReasonErrorKey: "The media data could not be decoded. It may be damaged.",
    ])

    #expect(ExportProgress.message(for: error) == "Cannot Decode. The media data could not be decoded. It may be damaged.")
}

@Test func otherFailuresKeepTheirOwnDescription() {
    #expect(ExportProgress.message(for: GIFExporter.ExportError.noVideoTrack) == "The recording has no video track")
}

@Test func theDiagnosisNamesEachErrorDownTheChain() {
    let underlying = NSError(domain: NSOSStatusErrorDomain, code: -12_909)
    let error = NSError(domain: AVFoundationErrorDomain, code: AVError.decodeFailed.rawValue, userInfo: [NSUnderlyingErrorKey: underlying])

    #expect(ExportProgress.diagnosis(of: error) == "AVFoundationErrorDomain -11821 ← NSOSStatusErrorDomain -12909")
}

extension CompositingMediaTests {
    /// The fractions reported, in order, and a closure that collects them.
    private final class Reports: Sendable {
        let values = Mutex<[Double]>([])
        var report: @Sendable (Double) -> Void { { value in self.values.withLock { $0.append(value) } } }
        var all: [Double] { values.withLock { $0 } }
    }

    private func expectSteadyProgressToTheEnd(_ values: [Double], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(values.last == 1, sourceLocation: sourceLocation)
        #expect(values.allSatisfy { (0...1).contains($0) }, sourceLocation: sourceLocation)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }, "never goes back", sourceLocation: sourceLocation)
    }

    @Test func anMP4ExportReportsProgressToTheEnd() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        try await writeScreenRecording(to: input, seconds: 2, audio: true)
        let reports = Reports()

        try await VideoTrimmer.trim(input, range: TrimRange(start: 0.5, end: 2, duration: 2), to: folder.appendingPathComponent("out.mp4"), progress: reports.report)

        expectSteadyProgressToTheEnd(reports.all)
    }

    @Test func aRetimedExportReportsEachStepInTurn() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("in.mp4")
        try await writeScreenRecording(to: input, seconds: 3, audio: true)
        let reports = Reports()

        try await VideoTrimmer.trim(input, range: TrimRange(duration: 3), speed: 1.5, to: folder.appendingPathComponent("fast.mp4"), progress: reports.report)

        let values = reports.all
        expectSteadyProgressToTheEnd(values)
        // The video step ends at 0.7 and the audio step at 0.85 before the copy finishes the whole.
        #expect(values.contains { abs($0 - 0.7) < 1e-9 })
        #expect(values.contains { abs($0 - 0.85) < 1e-9 })
    }

    @Test func aDrawnExportReportsProgressToTheEnd() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("in.mp4")
        let size = CGSize(width: 320, height: 240)
        try await writeSolidVideo(to: source, color: .red, size: size, seconds: 2)
        let reports = Reports()

        try await ProjectExporter.export(
            Project(source: source, duration: 2, canvasSize: size, hasAudio: false), to: folder.appendingPathComponent("out.mp4"), progress: reports.report
        )

        expectSteadyProgressToTheEnd(reports.all)
    }

    @Test func aGIFExportReportsNoSkippedFramesForAGoodVideo() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4")
        try await writeSyntheticVideo(to: video, seconds: 1, fps: 30, width: 320, height: 240)
        let reports = Reports()

        let result = try await GIFExporter.export(videoURL: video, to: folder.appendingPathComponent("out.gif"), progress: reports.report)

        #expect(result.skippedFrames == 0)
        expectSteadyProgressToTheEnd(reports.all)
    }
}
