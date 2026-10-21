import AVFoundation
import Foundation
import Synchronization
import UniformTypeIdentifiers

extension TrimRange {
    public var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
    }
}

/// The Mac's `VideoAssembler`: AVFoundation compositions and export sessions, and an asset writer where export can't.
public struct AVVideoAssembler: VideoAssembler {
    public init() {}

    public func trim(_ input: URL, kept: [TrimRange], speed: Double, muted: Bool, to output: URL, as fileType: String?) async throws -> Bool {
        let asset = AVURLAsset(url: input)
        let fileType = try fileType.map(AVFileType.init(rawValue:)) ?? Self.fileType(of: input)
        let audio = muted ? [] : try await asset.loadTracks(withMediaType: .audio)
        if speed != 1, !audio.isEmpty {
            return try await retime(asset, audio: audio, kept: kept, speed: speed, to: output, as: fileType)
        }
        // One section with its sound as it is exports straight from the file. Otherwise a composition
        // joins the kept sections, with the sound when there's any to keep or the video alone retimed.
        let edited = kept.count > 1 || audio.isEmpty && (muted || speed != 1) ? try await composition(of: asset, kept: kept, audio: audio, speed: speed) : nil
        let source: AVAsset = edited ?? asset

        let passthrough = await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: source, outputFileType: fileType)
        let preset = passthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let export = AVAssetExportSession(asset: source, presetName: preset) else {
            throw VideoTrimmer.TrimError.exportFailed
        }
        guard export.supportedFileTypes.contains(fileType) else {
            throw VideoTrimmer.TrimError.unsupportedFileType
        }
        if edited == nil {
            export.timeRange = kept[0].timeRange
        }
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try await export.export(to: output, as: fileType)
        return passthrough
    }

    private static func fileType(of url: URL) throws -> AVFileType {
        guard let identifier = UTType(filenameExtension: url.pathExtension)?.identifier else {
            throw VideoTrimmer.TrimError.unsupportedFileType
        }
        return AVFileType(rawValue: identifier)
    }

    /// The `kept` sections of the video tracks and of `audio`, end to end and retimed by `speed`.
    private func composition(of asset: AVURLAsset, kept: [TrimRange], audio: [AVAssetTrack], speed: Double) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        for track in try await asset.loadTracks(withMediaType: .video) {
            try insert(kept, of: track, into: composition, speed: speed)
                .preferredTransform = try await track.load(.preferredTransform)
        }
        for track in audio {
            try insert(kept, of: track, into: composition, speed: speed)
        }
        return composition
    }

    /// Copying scaled audio only stretches it with an edit list, which most players ignore, so the
    /// audio is rendered at the new rate. Export can't copy retimed video alongside that audio, so
    /// each is written on its own and the samples of both are copied into `output`.
    private func retime(_ asset: AVURLAsset, audio: [AVAssetTrack], kept: [TrimRange], speed: Double, to output: URL, as fileType: AVFileType) async throws -> Bool {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("Shot/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let videoURL = scratch.appendingPathComponent("video.mp4")
        let passthrough = try await trim(asset.url, kept: kept, speed: speed, muted: true, to: videoURL, as: AVFileType.mp4.rawValue)

        let retimed = AVMutableComposition()
        for track in audio {
            try insert(kept, of: track, into: retimed, speed: speed)
        }
        guard let export = AVAssetExportSession(asset: retimed, presetName: AVAssetExportPresetAppleM4A) else {
            throw VideoTrimmer.TrimError.exportFailed
        }
        export.audioTimePitchAlgorithm = .spectral
        let audioURL = scratch.appendingPathComponent("audio.m4a")
        try await export.export(to: audioURL, as: .m4a)

        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try await mux(video: videoURL, audio: audioURL, to: output, as: fileType)
        return passthrough
    }

    /// Copies the samples of `video`'s video track and `audio`'s audio track into one file.
    private func mux(video: URL, audio: URL, to output: URL, as fileType: AVFileType) async throws {
        let writer = try AVAssetWriter(outputURL: output, fileType: fileType)
        let videoAsset = AVURLAsset(url: video)
        let duration = try await videoAsset.load(.duration)
        var copies: [(reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)] = []
        for (asset, type) in [(videoAsset, AVMediaType.video), (AVURLAsset(url: audio), .audio)] {
            guard let track = try await asset.loadTracks(withMediaType: type).first else {
                throw VideoTrimmer.TrimError.exportFailed
            }
            let reader = try AVAssetReader(asset: asset)
            // The audio encoder pads the end a little; keep the audio within the video.
            reader.timeRange = CMTimeRange(start: .zero, duration: duration)
            let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(trackOutput)
            let (formats, transform) = try await track.load(.formatDescriptions, .preferredTransform)
            let input = AVAssetWriterInput(mediaType: type, outputSettings: nil, sourceFormatHint: formats.first)
            input.transform = transform
            writer.add(input)
            copies.append((reader, trackOutput, input))
        }
        guard writer.startWriting() else {
            throw writer.error ?? VideoTrimmer.TrimError.exportFailed
        }
        writer.startSession(atSourceTime: .zero)
        do {
            for copy in copies where !copy.reader.startReading() {
                throw copy.reader.error ?? VideoTrimmer.TrimError.exportFailed
            }
            // Reading a sample blocks until it's decoded, so the copy runs on a queue of its own rather than
            // holding one of Swift's few cooperative threads, which the readers' other work may be waiting for.
            nonisolated(unsafe) let (pending, sharedWriter) = (copies, writer)
            let cancelled = Mutex(false)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue(label: "Shot.mux").async {
                        continuation.resume(with: Result {
                            try Self.copySamples(pending, into: sharedWriter) { cancelled.withLock { $0 } }
                        })
                    }
                }
            } onCancel: {
                cancelled.withLock { $0 = true }
            }
        } catch {
            // Deletes what was written so far.
            writer.cancelWriting()
            throw error
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? VideoTrimmer.TrimError.exportFailed
        }
    }

    /// Copies every sample from each reader output to its writer input, blocking until all are written.
    private static func copySamples(_ copies: [(reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)], into writer: AVAssetWriter, isCancelled: () -> Bool) throws {
        var copies = copies
        // The writer interleaves the tracks, so it takes from whichever one it's ready for.
        while !copies.isEmpty {
            if isCancelled() {
                throw CancellationError()
            }
            var appended = false
            for index in copies.indices.reversed() where copies[index].input.isReadyForMoreMediaData {
                if let buffer = copies[index].output.copyNextSampleBuffer() {
                    guard copies[index].input.append(buffer) else {
                        throw writer.error ?? VideoTrimmer.TrimError.exportFailed
                    }
                    appended = true
                } else {
                    if copies[index].reader.status == .failed {
                        throw copies[index].reader.error ?? VideoTrimmer.TrimError.exportFailed
                    }
                    copies[index].input.markAsFinished()
                    copies.remove(at: index)
                }
            }
            if !appended {
                // A writer that has stopped never takes more data, so waiting for it would never end.
                guard writer.status == .writing else {
                    throw writer.error ?? VideoTrimmer.TrimError.exportFailed
                }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }

    /// Inserts the `kept` sections of `track` end to end at the start of `composition`, playing them at `speed`.
    @discardableResult
    private func insert(_ kept: [TrimRange], of track: AVAssetTrack, into composition: AVMutableComposition, speed: Double) throws -> AVMutableCompositionTrack {
        guard let copy = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoTrimmer.TrimError.exportFailed
        }
        var cursor = CMTime.zero
        for section in kept {
            let source = section.timeRange
            try copy.insertTimeRange(source, of: track, at: cursor)
            cursor = cursor + source.duration
        }
        if speed != 1 {
            copy.scaleTimeRange(CMTimeRange(start: .zero, duration: cursor), toDuration: CMTimeMultiplyByFloat64(cursor, multiplier: 1 / speed))
        }
        return copy
    }

    public func concatenate(_ segments: [URL], audio: [VideoConcatenator.SegmentAudio], to output: URL, muting muted: CutList) async throws {
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
            throw VideoConcatenator.ConcatError.exportFailed
        }
        try await export.export(to: output, as: .mp4)
    }

    private func silence(_ tracks: [AVMutableCompositionTrack], over muted: CutList, before end: CMTime) {
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
    private func mix(_ audio: [VideoConcatenator.SegmentAudio], of segments: [URL], mutingMicrophone muted: CutList, to output: URL) async throws -> Bool {
        let composition = AVMutableComposition()
        guard let system = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let microphone = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoConcatenator.ConcatError.exportFailed
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
            throw VideoConcatenator.ConcatError.exportFailed
        }
        try await export.export(to: output, as: .m4a)
        return true
    }
}
