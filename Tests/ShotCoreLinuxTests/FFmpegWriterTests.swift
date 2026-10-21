import Foundation
import Testing
@testable import ShotCoreLinux

// FFmpegWriter and FFmpegReader's drawn projects on the ffmpeg installed: projects of the clips in Tests/Fixtures/video,
// probed and read back, and the projects of Tests/Fixtures/compositor, drawn from still videos of their source frames
// and compared with the frames the Mac drew of them.

/// Writes `project` to a new file in `folder` as MP4.
private func write(_ project: Project, in folder: URL, as fileType: String = "public.mpeg-4") async throws -> URL {
    let output = folder.appendingPathComponent("out.mp4")
    try await FFmpegWriter().write(project, to: output, as: fileType, canvasType: CairoCanvas.self) { _ in .h264 }
    return output
}

/// A clip of `source` from `sourceStart` to `sourceEnd`, at `start` on the timeline, as loud as `volume`.
private func sound(_ source: URL, _ sourceStart: Double, _ sourceEnd: Double, at start: Double, volume: Double = 1) -> Clip {
    Clip(source: source, sourceDuration: 2, sourceStart: sourceStart, sourceEnd: sourceEnd, start: start, volume: volume)
}

/// The frames of `project` at `times`, as `FFmpegReader` draws them.
private func drawn(_ project: Project, at times: [Double], maxSize: CGSize = .zero) async throws -> [VideoFrame] {
    var frames: [VideoFrame] = []
    try await FFmpegReader().frames(of: project, canvasType: CairoCanvas.self).readFrames(at: times, maxSize: maxSize, tolerance: 0) { frames.append($0) }
    return frames
}

@Suite(.serialized, .enabled(if: hasFFmpeg, "ffmpeg isn't installed")) struct FFmpegWriterTests {
    @Test func aProjectOfOneClipIsWrittenWithItsPictureAndSound() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = try await write(Project(source: timed, duration: 2, canvasSize: CGSize(width: 160, height: 120), hasAudio: true), in: folder)
        let written = try await probe(output)
        #expect(abs(written.duration - 2) < 0.1 && written.size == CGSize(width: 160, height: 120) && written.hasAudio)
        #expect(written.streams.first { $0.codecType == "video" }?.codecName == "h264" && written.frameRate == 30)
        // Frames 3, 30 and 57, gray 12, 120 and 228, through two encodes.
        let grays = try await frames(of: output, at: [0.1, 1, 1.9]).map { gray(try $0.decoded.get().image) }
        #expect(zip(grays, [12, 120, 228]).allSatisfy { abs($0 - $1) <= 6 }, "\(grays)")
        let loudness = try await levels(of: output, at: [0.5, 1.5])
        #expect(abs(loudness[0] - 0.17) < 0.03 && loudness[1] < 0.01, "\(loudness)")
    }

    @Test func aWrittenProjectReplacesWhatWasThere() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("old".utf8).write(to: folder.appendingPathComponent("out.mp4"))
        let output = try await write(Project(source: rotated, duration: 1, canvasSize: CGSize(width: 90, height: 160), hasAudio: false), in: folder)
        let written = try await probe(output)
        #expect(written.size == CGSize(width: 90, height: 160) && !written.hasAudio)
        // Upright, with the red corner at the top right.
        let image = try #require(try await frames(of: output, at: [0.5]).first?.decoded.get().image)
        let corner = color(image, x: 0.9, y: 0.05)
        #expect(corner.r > 200 && corner.g < 60 && corner.b < 60, "\(corner)")
    }

    @Test func aProjectThatNeedsHEVCIsWrittenInIt() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var rate: Int?
        let output = folder.appendingPathComponent("out.mov")
        let project = Project(source: timed, duration: 2, canvasSize: CGSize(width: 160, height: 120), hasAudio: false)
        try await FFmpegWriter().write(project, to: output, as: "com.apple.quicktime-movie", canvasType: CairoCanvas.self) { frameRate in
            rate = frameRate
            return .hevc
        }
        #expect(rate == 30)
        let written = try await probe(output)
        #expect(written.streams.first { $0.codecType == "video" }?.codecName == "hevc" && abs(written.duration - 2) < 0.1)
        let grays = try await frames(of: output, at: [1]).map { gray(try $0.decoded.get().image) }
        #expect(grays.count == 1 && abs(grays[0] - 120) <= 6, "\(grays)")
    }

    @Test func twoClipsWithACutAndAFadeAreWrittenAsTheMacDrawsThem() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let whole = Project(source: timed, duration: 2, canvasSize: CGSize(width: 160, height: 120), hasAudio: true)
        let cut = try #require(whole.deleting(range: 0.5..<1))
        let second = try #require(cut.main.clips.last)
        let project = try #require(cut.applying(.fadeIn, toClip: second.id))
        let output = try await write(project, in: folder)
        #expect(abs(try await probe(output).duration - 1.5) < 0.1)
        // Frame 7 of the first clip; then frames 37 and 52, gray 148 and 208, of the second as it fades in from black.
        let faded = try #require(project.main.clips.last).values(atTimeline: 0.75).opacity
        let grays = try await frames(of: output, at: [0.25, 0.5, 0.75, 1.25]).map { gray(try $0.decoded.get().image) }
        let expected = [28, 0, Int((148 * faded).rounded()), 208]
        #expect(zip(grays, expected).allSatisfy { abs($0 - $1) <= 8 }, "\(grays), not \(expected)")
        // The sound is cut with the picture: the tone, then the silent second.
        let loudness = try await levels(of: output, at: [0.25, 1])
        #expect(loudness[0] > 0.12 && loudness[1] < 0.01, "\(loudness)")
    }

    @Test(arguments: compositorLimits.map(\.name))
    func aStyledProjectIsWrittenAsTheMacDrewIt(name: String) async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let golden = try compositorGolden(name)
        // Still videos of its source frames, which ffv1 keeps exactly, in place of its clips' sources.
        var project = golden.project
        let shown = PortableCompositor(project: project, canvasType: CairoCanvas.self).pictures(at: golden.time)
        let tools = try FFmpegTools.find()
        for (index, picture) in shown.enumerated() {
            let still = folder.appendingPathComponent("\(index).mkv")
            _ = try await Subprocess.output(tools.ffmpeg, [
                "-v", "error", "-nostdin", "-loop", "1", "-framerate", "30", "-i", compositorSourceFrame(name, index).path, "-t", "2", "-c:v", "ffv1", "-pix_fmt", "bgr0", still.path,
            ])
            for track in project.tracks.indices {
                for clip in project.tracks[track].clips.indices where project.tracks[track].clips[clip].id == picture.clip.id {
                    project.tracks[track].clips[clip].source = still
                }
            }
        }
        // Read as it's drawn, it's what CompositorGoldenTests draws from the same frames.
        let frame = try #require(try await drawn(project, at: [golden.time]).first?.decoded.get())
        #expect(frame.time == golden.time)
        let limit = try #require(compositorLimits.first { $0.name == name })
        let (share, worst) = try compareWithCompositorGolden(frame.image.bitmap, with: name)
        #expect(share <= limit.share && worst <= limit.worst)
        // Written, H.264 halves the colour's resolution, which blurs it at edges.
        let output = try await write(project, in: folder)
        let written = try #require(try await frames(of: output, at: [golden.time]).first?.decoded.get().image)
        let (encodedShare, _) = try compareWithCompositorGolden(written.bitmap, with: name, tolerance: 40)
        #expect(encodedShare <= 0.01, "\(name): \(String(format: "%.2f", encodedShare * 100))% differ by more than 40")
    }

    @Test func eachClipsSoundIsMixedAtItsVolume() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var project = Project(source: timed, duration: 2, canvasSize: CGSize(width: 160, height: 120), hasAudio: false)
        project.tracks.append(Track(kind: .audio, clips: [sound(tone, 0, 1, at: 0), sound(tone, 1, 2, at: 1, volume: 0.25)]))
        // A muted track isn't heard.
        project.tracks.append(Track(kind: .audio, clips: [sound(tone, 0, 2, at: 0)], isMuted: true))
        let loudness = try await levels(of: try await write(project, in: folder), at: [0.5, 1.5])
        let tone = try await levels(of: tone, at: [0.5])[0]
        #expect(abs(loudness[0] - tone) < tone * 0.1 && abs(loudness[1] - tone / 4) < tone * 0.05, "\(loudness) of \(tone)")
    }

    @Test func aClipsVolumeFollowsItsKeyframes() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var project = Project(source: timed, duration: 2, canvasSize: CGSize(width: 160, height: 120), hasAudio: false)
        var rising = sound(tone, 0, 2, at: 0)
        rising.animation.volume = [Keyframe(time: 0, value: 0), Keyframe(time: 2, value: 1)]
        project.tracks.append(Track(kind: .audio, clips: [rising]))
        let loudness = try await levels(of: try await write(project, in: folder), at: [0.5, 1.5])
        let tone = try await levels(of: tone, at: [0.5])[0]
        #expect(abs(loudness[0] - tone / 4) < tone * 0.06 && abs(loudness[1] - tone * 3 / 4) < tone * 0.06, "\(loudness) of \(tone)")
    }

    @Test func aProjectsFramesAreReadAsTheyreDrawnInTheOrderAsked() async throws {
        let project = Project(source: timed, duration: 2, canvasSize: CGSize(width: 160, height: 120), hasAudio: true)
        let frames = try await FFmpegReader().frames(of: project, canvasType: CairoCanvas.self)
        #expect(abs(frames.duration - 2) < 0.001 && frames.size == CGSize(width: 160, height: 120))
        let read = try await drawn(project, at: [1, 0.1, 1], maxSize: CGSize(width: 80, height: 0))
        #expect(read.map(\.requestedTime) == [1, 0.1, 1])
        let images = try read.map { try $0.decoded.get().image }
        #expect(images.allSatisfy { $0.width == 80 && $0.height == 60 })
        let grays = images.map(gray)
        #expect(zip(grays, [120, 12, 120]).allSatisfy { abs($0 - $1) <= 2 }, "\(grays)")
    }

    @Test func aProjectThatCantBeWrittenSaysWhy() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Project(source: timed, duration: 2, canvasSize: CGSize(width: 160, height: 120), hasAudio: true)
        await #expect(throws: ProjectExporter.ExportError.unsupportedFileType) { try await write(project, in: folder, as: "com.compuserve.gif") }
        let missing = Project(source: folder.appendingPathComponent("gone.mp4"), duration: 2, canvasSize: CGSize(width: 160, height: 120), hasAudio: false)
        await #expect { try await write(missing, in: folder) } throws: { error in
            guard case CompositionBuilder.BuildError.cannotInsert("gone.mp4") = error else { return false }
            return true
        }
        let silent = Project(source: tone, duration: 2, canvasSize: CGSize(width: 160, height: 120), hasAudio: false)
        await #expect { try await FFmpegReader().frames(of: silent, canvasType: CairoCanvas.self) } throws: { error in
            guard case CompositionBuilder.BuildError.noVideo("tone.m4a") = error else { return false }
            return true
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("out.mp4").path))
    }
}
