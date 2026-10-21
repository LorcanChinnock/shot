import Foundation

/// Linux's `VideoAssembler`: `ffmpeg`, copying the video where the cuts allow and encoding it again where they don't, as
/// `FFmpeg.trim` and `FFmpeg.concatenate` plan, and encoding it again when copying fails.
public struct FFmpegAssembler: VideoAssembler {
    public init() {}

    private static let log = ShotLog.shot("video")

    public func trim(_ input: URL, kept: [TrimRange], speed: Double, muted: Bool, to output: URL, as fileType: String?) async throws -> Bool {
        guard let type = fileType ?? FFmpeg.fileType(forExtension: input.pathExtension), let muxer = FFmpeg.muxer(for: type) else {
            throw VideoTrimmer.TrimError.unsupportedFileType
        }
        let tools = try FFmpegTools.find()
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        return try await withScratchFolder { scratch in
            let concatList = scratch.appendingPathComponent("list.txt")
            do {
                let probe = try await tools.probe(input)
                let source = FFmpeg.Source(path: input.path, hasAudio: probe.hasAudio, frameRate: probe.frameRate)
                func job(copying: Bool) -> FFmpeg.Job {
                    FFmpeg.trim(source, kept: kept, speed: speed, muted: muted, to: output.path, as: muxer, scratch: scratch.path, copying: copying)
                }
                let copied = job(copying: true)
                do {
                    try await tools.run(copied, listedAt: concatList)
                    return copied.copiesVideo
                } catch let error as Subprocess.Failure where copied.copiesVideo {
                    // The format may not take the video as it is.
                    Self.log.error("Couldn't copy \(input.lastPathComponent, privacy: .public)'s video, so it's encoded again: \(error.localizedDescription, privacy: .public)")
                    try await tools.run(job(copying: false), listedAt: concatList)
                    return false
                }
            } catch {
                try? FileManager.default.removeItem(at: output)
                if error is CancellationError {
                    throw error
                }
                Self.log.error("Couldn't trim \(input.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw VideoTrimmer.TrimError.exportFailed
            }
        }
    }

    public func concatenate(_ segments: [URL], audio: [VideoConcatenator.SegmentAudio], to output: URL, muting muted: CutList) async throws {
        let tools = try FFmpegTools.find()
        try await withScratchFolder { scratch in
            let concatList = scratch.appendingPathComponent("list.txt")
            do {
                var durations: [Double] = []
                var hasAudio = false
                for segment in segments {
                    let probe = try await tools.probe(segment)
                    durations.append(probe.duration)
                    hasAudio = hasAudio || probe.hasAudio
                }
                var sounds: [FFmpeg.SegmentSound] = []
                for files in audio {
                    // A source that never sent a sample has no file, or one with no sound.
                    func sound(_ url: URL) async -> String? {
                        try? await tools.probe(url).hasAudio ? url.path : nil
                    }
                    sounds.append(FFmpeg.SegmentSound(system: await sound(files.system), microphone: await sound(files.microphone)))
                }
                let job = FFmpeg.concatenate(
                    segments.map(\.path), durations: durations, sounds: sounds, hasAudio: hasAudio, muting: muted.cuts, to: output.path, concatList: concatList.path
                )
                try await tools.run(job, listedAt: concatList)
            } catch {
                try? FileManager.default.removeItem(at: output)
                if error is CancellationError {
                    throw error
                }
                Self.log.error("Couldn't join \(segments.count) segments: \(error.localizedDescription, privacy: .public)")
                throw VideoConcatenator.ConcatError.exportFailed
            }
        }
    }
}
