import AVFoundation

public enum VideoConcatenator {
    public enum ConcatError: LocalizedError {
        case noSegments
        case exportFailed

        public var errorDescription: String? {
            switch self {
            case .noSegments: "Nothing was recorded"
            case .exportFailed: "Could not join the recording's segments"
            }
        }
    }

    /// A segment's system audio and microphone, recorded to their own files so muting can silence only the microphone.
    public struct SegmentAudio: Sendable {
        public let system: URL
        public let microphone: URL

        public init(system: URL, microphone: URL) {
            self.system = system
            self.microphone = microphone
        }

        public var files: [URL] { [system, microphone] }
    }

    /// Joins recording segments end to end without re-encoding the video; one segment with nothing muted is moved as is.
    /// `muted` holds stretches of the joined recording, in seconds, that become silent.
    /// With `audio`, one per segment, the segments' own audio is replaced by a mix of those files, and only the microphone is muted.
    public static func concatenate(_ segments: [URL], audio: [SegmentAudio] = [], to output: URL, muting muted: CutList = CutList()) async throws {
        guard let first = segments.first else {
            throw ConcatError.noSegments
        }
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        if segments.count == 1, muted.isEmpty, audio.isEmpty {
            try FileManager.default.moveItem(at: first, to: output)
            return
        }
        let composition = AVMutableComposition()
        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)
            if audio.isEmpty {
                try await composition.insertTimeRange(range, of: asset, at: cursor)
            } else if let video = try await asset.loadTracks(withMediaType: .video).first,
                      let target = composition.tracks(withMediaType: .video).first ?? composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try target.insertTimeRange(range, of: video, at: cursor)
            }
            cursor = cursor + duration
        }
        if audio.isEmpty {
            silence(composition.tracks(withMediaType: .audio), over: muted, before: cursor)
        }
        let mixURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: mixURL) }
        let mixed = AVURLAsset(url: mixURL)
        if !audio.isEmpty, try await mix(audio, of: segments, mutingMicrophone: muted, to: mixURL),
           let track = try await mixed.loadTracks(withMediaType: .audio).first,
           let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let length = min(try await track.load(.timeRange).end, cursor)
            try withExtendedLifetime(mixed) { try target.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: .zero) }
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw ConcatError.exportFailed
        }
        try await export.export(to: output, as: .mp4)
        for url in segments + audio.flatMap(\.files) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func silence(_ tracks: [AVMutableCompositionTrack], over muted: CutList, before end: CMTime) {
        for track in tracks {
            for cut in muted.cuts {
                let range = CMTimeRange(start: CMTime(seconds: cut.lowerBound, preferredTimescale: 600), end: min(CMTime(seconds: cut.upperBound, preferredTimescale: 600), end))
                guard range.duration > .zero else {
                    continue
                }
                track.removeTimeRange(range)
                track.insertEmptyTimeRange(range)
            }
        }
    }

    /// Lays each segment's audio files at its place in the recording and mixes them to one track; `false` when there was no audio.
    private static func mix(_ audio: [SegmentAudio], of segments: [URL], mutingMicrophone muted: CutList, to output: URL) async throws -> Bool {
        let composition = AVMutableComposition()
        guard let system = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let microphone = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ConcatError.exportFailed
        }
        var cursor = CMTime.zero
        for (segment, files) in zip(segments, audio) {
            let duration = try await AVURLAsset(url: segment).load(.duration)
            for (url, target) in [(files.system, system), (files.microphone, microphone)] {
                let source = AVURLAsset(url: url)
                // A source that never sent a sample has no file.
                guard let track = try? await source.loadTracks(withMediaType: .audio).first, let length = try? await track.load(.timeRange).end else {
                    continue
                }
                // A track holds its asset weakly, and inserting fails once the asset is gone.
                try withExtendedLifetime(source) { try target.insertTimeRange(CMTimeRange(start: .zero, duration: min(length, duration)), of: track, at: cursor) }
            }
            cursor = cursor + duration
        }
        silence([microphone], over: muted, before: cursor)
        for track in composition.tracks where track.segments.allSatisfy(\.isEmpty) {
            composition.removeTrack(track)
        }
        guard !composition.tracks.isEmpty else {
            return false
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw ConcatError.exportFailed
        }
        try await export.export(to: output, as: .m4a)
        return true
    }
}
