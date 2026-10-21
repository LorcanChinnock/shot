import Foundation
import Testing
@testable import ShotCoreLinux

// FFmpegReader and FFmpegAssembler on the ffmpeg installed, reading the clips in Tests/Fixtures/video, which
// ShotCoreAppleTests' VideoFixtureTests wrote with AVFoundation and reads the same way, and the cases of
// ShotCoreAppleTests' VideoTrimTests, VideoConcatenatorTests and MediaProbeTests that need no Apple framework.

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/video")
private let timed = fixtures.appendingPathComponent("timed.mp4")
private let rotated = fixtures.appendingPathComponent("rotated.mp4")
private let tone = fixtures.appendingPathComponent("tone.m4a")

private let hasFFmpeg = (try? FFmpegTools.find()) != nil || ProcessInfo.processInfo.environment["CI"] != nil

/// The gray level of `image`'s middle pixel.
private func gray(_ image: PlatformImage) -> Int {
    Int(image.bitmap[image.width / 2, image.height / 2].g)
}

/// The colour of `image` at (`x`, `y`), as fractions of it from the top left.
private func color(_ image: PlatformImage, x: Double, y: Double) -> (r: Int, g: Int, b: Int) {
    let pixel = image.bitmap[Int(x * Double(image.width)), Int(y * Double(image.height))]
    return (Int(pixel.r), Int(pixel.g), Int(pixel.b))
}

/// The frames `FFmpegReader` reads from `url` at `times`.
private func frames(of url: URL, at times: [Double], maxSize: CGSize = .zero, tolerance: Double? = 0) async throws -> [VideoFrame] {
    var frames: [VideoFrame] = []
    try await FFmpegReader().readFrames(of: url, at: times, maxSize: maxSize, tolerance: tolerance) { frames.append($0) }
    return frames
}

/// How loud `url` is over the 0.2 s around each of `times`.
private func levels(of url: URL, at times: [Double]) async throws -> [Float] {
    var samples: [Float] = []
    try await FFmpegReader().readMonoSamples(of: url, sampleRate: 8000) { samples += $0 }
    return times.map { time in
        let start = max(0, Int((time - 0.1) * 8000)), end = min(samples.count, Int((time + 0.1) * 8000))
        return start < end ? AudioLevel.rms(Array(samples[start..<end])) : 0
    }
}

private func probe(_ url: URL) async throws -> FFmpeg.Probe {
    try await FFmpegTools.find().probe(url)
}

@Suite(.serialized, .enabled(if: hasFFmpeg, "ffmpeg isn't installed")) struct FFmpegTests {
    // MARK: Reading

    @Test func theTimedClipReadsAsAVFoundationReadsIt() async throws {
        let reader = FFmpegReader()
        let info = try await reader.info(of: timed)
        #expect(abs(info.duration - 2) < 0.05 && info.size == CGSize(width: 160, height: 120) && info.hasAudio)
        let rates = try await reader.bitRates(of: timed)
        #expect(abs(rates.video - 12_500) < 2_500 && abs(rates.audio - 17_300) < 3_500, "\(rates)")
        let sync = try #require(try await reader.syncTimes(atOrBefore: [0.2, 0.7, 1.9], in: timed))
        #expect(zip(sync, [0, 0.5, 1.5]).allSatisfy { abs($0 - $1) < 0.001 }, "\(sync)")

        let read = try await frames(of: timed, at: [1, 0.1, 1])
        #expect(read.map(\.requestedTime) == [1, 0.1, 1])
        let decoded = try read.map { try $0.decoded.get() }
        #expect(zip(decoded.map(\.time), [1, 0.1, 1]).allSatisfy { abs($0 - $1) < 0.001 })
        // Frames 30 and 3, gray 120 and 12 as written, which AVFoundation reads as 131 and 10.
        #expect(zip(decoded.map { gray($0.image) }, [120, 12, 120]).allSatisfy { abs($0 - $1) <= 12 }, "\(decoded.map { gray($0.image) })")

        var samples: [Float] = []
        try await reader.readMonoSamples(of: timed, sampleRate: 8000) { samples += $0 }
        #expect(abs(samples.count - 16_000) < 100)
        // The tone, at a quarter of full scale, then silence.
        #expect(abs(AudioLevel.rms(Array(samples[1600..<6400])) - 0.17) < 0.02 && AudioLevel.rms(Array(samples[9600..<14400])) < 0.01)
        let sound = try await reader.info(of: tone)
        #expect(abs(sound.duration - 2) < 0.05 && sound.size == nil && sound.hasAudio)
    }

    @Test func aTurnedClipReadsUprightAtItsPlayingSize() async throws {
        let info = try await FFmpegReader().info(of: rotated)
        #expect(info.size == CGSize(width: 90, height: 160) && !info.hasAudio)
        let image = try #require(try await frames(of: rotated, at: [0.5], maxSize: CGSize(width: 45, height: 0), tolerance: nil).first?.decoded.get().image)
        #expect(image.width == 45 && image.height == 80)
        // Turned a quarter clockwise, the red corner is at the top right.
        let corner = color(image, x: 0.9, y: 0.1), rest = color(image, x: 0.1, y: 0.1)
        #expect(corner.r > 180 && corner.g < 90, "\(corner)")
        #expect(rest.g > 140 && rest.r < 130, "\(rest)")
    }

    @Test func framesComeInTheOrderAskedFromRunsInTimeOrder() async throws {
        // One run decodes them in time order, so those asked for out of order wait for the ones before them.
        let read = try await frames(of: timed, at: [1.9, 0, 1, 0.5, 1.9])
        #expect(read.map(\.requestedTime) == [1.9, 0, 1, 0.5, 1.9])
        let decoded = try read.map { try $0.decoded.get() }
        #expect(zip(decoded.map(\.time), [1.9, 0, 1, 0.5, 1.9]).allSatisfy { abs($0 - $1) < 0.001 })
        #expect(zip(decoded.map { gray($0.image) }, [228, 0, 120, 60, 228]).allSatisfy { abs($0 - $1) <= 12 }, "\(decoded.map { gray($0.image) })")
        // Without a tolerance, the nearest sync frame is quickest.
        let quick = try await frames(of: timed, at: [0.7, 1.35], tolerance: nil).map { try $0.decoded.get().time }
        #expect(zip(quick, [0.5, 1.5]).allSatisfy { abs($0 - $1) < 0.001 }, "\(quick)")
    }

    @Test func aClipWithNoPictureHasNoFramesAndOneWithNoSoundNoSamples() async throws {
        let read = try await frames(of: tone, at: [0.5, 1])
        #expect(read.map(\.requestedTime) == [0.5, 1])
        #expect(read.allSatisfy { (try? $0.decoded.get()) == nil })
        var called = false
        try await FFmpegReader().readMonoSamples(of: rotated, sampleRate: 8000) { _ in called = true }
        #expect(!called)
        #expect(try await FFmpegReader().syncTimes(atOrBefore: [1], in: tone) == nil)
    }

    @Test func probingAFileReadsItsDurationPictureAndSound() async throws {
        let media = try await MediaProbe.probe(timed)
        #expect(abs(media.duration - 2) < 0.1 && media.size == CGSize(width: 160, height: 120) && media.hasAudio)
    }

    @Test func probingSomethingThatIsntMediaFails() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: MediaProbe.ProbeError.self) { try await MediaProbe.probe(url) }
    }

    @Test func withoutFFmpegReadingSaysHowToInstallIt() async throws {
        #expect(throws: ShotCommandError.unavailable(FFmpegTools.missing)) { try FFmpegTools.find(environment: ["PATH": "/nowhere"]) }
        let found = try FFmpegTools.find(environment: ["PATH": "/nowhere", "SHOT_FFMPEG": try FFmpegTools.find().ffmpeg, "SHOT_FFPROBE": try FFmpegTools.find().ffprobe])
        #expect(found.ffmpeg.hasSuffix("ffmpeg") && found.ffprobe.hasSuffix("ffprobe"))
    }

    @Test func doctorReportsFFmpegsVersionAndEncoders() async throws {
        let facts = await FFmpegTools.doctorFacts()
        #expect(facts.ffmpeg != nil && facts.ffprobe != nil && facts.version != nil)
        #expect(facts.encoders.contains("aac"))
    }

    // MARK: Trimming

    @Test func trimsWithoutReencoding() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("out.mp4")
        let passthrough = try await VideoTrimmer.trim(timed, range: TrimRange(start: 0.7, end: 1.7, duration: 2), to: output)
        #expect(passthrough)
        let trimmed = try await probe(output)
        #expect(abs(trimmed.duration - 1) < 0.1 && trimmed.size == CGSize(width: 160, height: 120) && trimmed.hasAudio)
        #expect(trimmed.streams.first { $0.codecType == "video" }?.codecName == "h264")
        // It starts on frame 21, not the sync frame before it.
        let first = try #require(try await frames(of: output, at: [0]).first?.decoded.get().image)
        #expect(abs(gray(first) - 84) <= 12, "\(gray(first))")
    }

    @Test func trimReplacesAnExistingOutput() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("out.mp4")
        try Data("old".utf8).write(to: output)
        try await VideoTrimmer.trim(timed, range: TrimRange(start: 0.5, end: 1.5, duration: 2), to: output)
        #expect(abs(try await probe(output).duration - 1) < 0.1)
    }

    @Test func trimRefusesAFileTypeItCantWrite() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("out.gif")
        await #expect(throws: VideoTrimmer.TrimError.unsupportedFileType) {
            try await VideoTrimmer.trim(timed, range: TrimRange(duration: 2), to: output, as: "com.compuserve.gif")
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func trimCantTellTheFileTypeOfAnInputWithNoExtension() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("recording")
        try FileManager.default.copyItem(at: timed, to: input)
        await #expect(throws: VideoTrimmer.TrimError.unsupportedFileType) {
            try await VideoTrimmer.trim(input, range: TrimRange(duration: 2), to: folder.appendingPathComponent("out"))
        }
    }

    @Test func cutsAreEncodedAgainEvenOnSyncFrames() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("out.mov")
        let passthrough = try await VideoTrimmer.trim(timed, range: TrimRange(duration: 2), cuts: CutList([0.5..<1]), to: output)
        #expect(!passthrough)
        let trimmed = try await probe(output)
        #expect(abs(trimmed.duration - 1.5) < 0.1 && trimmed.hasAudio)
        // Source frame 30, at 1 s, follows the cut.
        let after = try #require(try await frames(of: output, at: [0.55]).first?.decoded.get().image)
        #expect(abs(gray(after) - 124) <= 12, "\(gray(after))")
    }

    @Test func cutsElsewhereAreEncodedAgain() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("out.mp4")
        let passthrough = try await VideoTrimmer.trim(timed, range: TrimRange(duration: 2), cuts: CutList([0.2..<1.2]), to: output)
        #expect(!passthrough)
        let trimmed = try await probe(output)
        #expect(abs(trimmed.duration - 1) < 0.1 && trimmed.size == CGSize(width: 160, height: 120) && trimmed.hasAudio)
        // Frame 36, at 1.2 s, follows the cut, and the tone stops with it.
        let after = try #require(try await frames(of: output, at: [0.25]).first?.decoded.get().image)
        #expect(abs(gray(after) - 148) <= 12, "\(gray(after))")
        let loudness = try await levels(of: output, at: [0.1, 0.6])
        #expect(loudness[0] > 0.1 && loudness[1] < 0.02, "\(loudness)")
    }

    @Test func aSpedUpTrimKeepsEveryFrameAndItsSound() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let copied = folder.appendingPathComponent("copied.mp4")
        #expect(try await VideoTrimmer.trim(timed, range: TrimRange(start: 0, end: 2, duration: 2), speed: 2, to: copied))
        let fast = try await probe(copied)
        #expect(abs(fast.duration - 1) < 0.1 && fast.hasAudio, "\(fast.duration)")
        let loudness = try await levels(of: copied, at: [0.25, 0.75])
        #expect(loudness[0] > 0.1 && loudness[1] < 0.02, "\(loudness)")

        let encoded = folder.appendingPathComponent("encoded.mp4")
        #expect(try await !VideoTrimmer.trim(timed, range: TrimRange(duration: 2), cuts: CutList([0.2..<0.4]), speed: 0.5, muted: true, to: encoded))
        let slow = try await probe(encoded)
        #expect(abs(slow.duration - 3.6) < 0.15 && !slow.hasAudio, "\(slow.duration)")
    }

    @Test func aTrimmedTurnedClipStillPlaysUpright() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, cuts) in [("copied.mp4", CutList()), ("encoded.mp4", CutList([0.2..<0.4]))] {
            let output = folder.appendingPathComponent(name)
            try await VideoTrimmer.trim(rotated, range: TrimRange(duration: 1), cuts: cuts, to: output)
            #expect(try await probe(output).size == CGSize(width: 90, height: 160), "\(name)")
            let image = try #require(try await frames(of: output, at: [0.1]).first?.decoded.get().image)
            #expect(color(image, x: 0.9, y: 0.1).r > 180, "\(name)")
        }
    }

    // MARK: Joining

    /// Copies of `timed`, which joining deletes.
    private func segments(_ count: Int, in folder: URL) throws -> [URL] {
        try (0..<count).map { index in
            let url = folder.appendingPathComponent("segment-\(index).mp4")
            try FileManager.default.copyItem(at: timed, to: url)
            return url
        }
    }

    @Test func concatenatesSegments() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let parts = try segments(2, in: folder)
        let output = folder.appendingPathComponent("out.mp4")
        try await VideoConcatenator.concatenate(parts, to: output)
        let joined = try await probe(output)
        #expect(abs(joined.duration - 4) < 0.15 && joined.hasAudio)
        #expect(!FileManager.default.fileExists(atPath: parts[0].path))
        // The second segment starts again at gray 0.
        let second = try #require(try await frames(of: output, at: [2.05]).first?.decoded.get().image)
        #expect(gray(second) <= 16, "\(gray(second))")

        let single = folder.appendingPathComponent("single.mp4")
        try await VideoConcatenator.concatenate(try segments(1, in: folder), to: single)
        #expect(FileManager.default.fileExists(atPath: single.path))
    }

    @Test func mutingSilencesOnlyThoseStretchesOfAudio() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("out.mp4")
        // Each segment has the tone for its first second.
        try await VideoConcatenator.concatenate(try segments(2, in: folder), to: output, muting: CutList([0.4..<0.8, 2.6..<10]))
        #expect(abs(try await probe(output).duration - 4) < 0.15)
        let loudness = try await levels(of: output, at: [0.2, 0.6, 2.3, 2.8])
        for (level, loud) in zip(loudness, [true, false, true, false]) {
            #expect((level > 0.05) == loud, "\(loudness)")
        }
    }

    @Test func aRecordingsOwnSoundFilesAreMixedWithOnlyTheMicrophoneMuted() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let parts = try segments(2, in: folder)
        // The system recorded nothing, so has no file; the microphone has the tone for each whole segment.
        let audio = try (0..<2).map { index in
            let microphone = folder.appendingPathComponent("microphone-\(index).m4a")
            try FileManager.default.copyItem(at: tone, to: microphone)
            return VideoConcatenator.SegmentAudio(system: folder.appendingPathComponent("system-\(index).m4a"), microphone: microphone)
        }
        let output = folder.appendingPathComponent("out.mp4")
        try await VideoConcatenator.concatenate(parts, audio: audio, to: output, muting: CutList([2.5..<3.5]))
        let joined = try await probe(output)
        #expect(abs(joined.duration - 4) < 0.15 && joined.hasAudio)
        let loudness = try await levels(of: output, at: [0.5, 1.5, 3, 3.75])
        for (level, loud) in zip(loudness, [true, true, false, true]) {
            #expect((level > 0.05) == loud, "\(loudness)")
        }
        #expect(!FileManager.default.fileExists(atPath: audio[0].microphone.path))
    }

    @Test func joiningNoSegmentsSaysNothingWasRecorded() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        await #expect(throws: VideoConcatenator.ConcatError.noSegments) {
            try await VideoConcatenator.concatenate([], to: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
