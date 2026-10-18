#if canImport(AVFoundation) && canImport(os) && canImport(UniformTypeIdentifiers)
import AVFoundation
import os
import UniformTypeIdentifiers

extension TrimRange {
    public var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
    }
}

public enum VideoTrimmer {
    public enum TrimError: LocalizedError {
        case unsupportedFileType
        case exportFailed
        case nothingLeft

        public var errorDescription: String? {
            switch self {
            case .unsupportedFileType: String(localized: "Can't write this kind of video")
            case .exportFailed: String(localized: "Couldn't export the trimmed video")
            case .nothingLeft: String(localized: "The cuts leave nothing to export")
            }
        }
    }

    /// Writes `range` of `input`, less `cuts`, to `output`, replacing `output`, in `fileType` or else the input's own.
    /// `speed` 2 plays it in half the time with every frame kept; `muted` leaves the audio out.
    /// Copies the video samples as they are when it can; returns false when it had to re-encode.
    @discardableResult
    public static func trim(_ input: URL, range: TrimRange, cuts: CutList = CutList(), speed: Double = 1, muted: Bool = false, to output: URL, as fileType: AVFileType? = nil) async throws -> Bool {
        let asset = AVURLAsset(url: input)
        let fileType = try fileType ?? Self.fileType(of: input)
        let kept = cuts.kept(in: range)
        guard !kept.isEmpty else {
            throw TrimError.nothingLeft
        }
        let audio = muted ? [] : try await asset.loadTracks(withMediaType: .audio)
        if speed != 1, !audio.isEmpty {
            return try await retime(asset, audio: audio, range: range, cuts: cuts, speed: speed, to: output, as: fileType)
        }
        // One section with its sound as it is exports straight from the file. Otherwise a composition
        // joins the kept sections, with the sound when there's any to keep or the video alone retimed.
        let edited = kept.count > 1 || audio.isEmpty && (muted || speed != 1) ? try await composition(of: asset, kept: kept, audio: audio, speed: speed) : nil
        let source: AVAsset = edited ?? asset

        let passthrough = await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: source, outputFileType: fileType)
        let preset = passthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let export = AVAssetExportSession(asset: source, presetName: preset) else {
            throw TrimError.exportFailed
        }
        guard export.supportedFileTypes.contains(fileType) else {
            throw TrimError.unsupportedFileType
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

    /// Roughly how many bytes `trim` writes with the same arguments, from the tracks' average bit rates.
    public static func estimatedSize(of input: URL, range: TrimRange, cuts: CutList = CutList(), speed: Double = 1, muted: Bool = false) async throws -> Int {
        let asset = AVURLAsset(url: input)
        var rates: [AVMediaType: Double] = [:]
        for type in [AVMediaType.video, .audio] {
            for track in try await asset.loadTracks(withMediaType: type) {
                rates[type, default: 0] += Double(try await track.load(.estimatedDataRate))
            }
        }
        let kept = cuts.kept(in: range)
        var videoLength: Double?
        if let video = try await asset.loadTracks(withMediaType: .video).first, try await video.load(.canProvideSampleCursors) {
            videoLength = copiedLength(of: kept, syncTimes: kept.map { syncTime(atOrBefore: $0.start, in: video) })
        }
        return estimatedBytes(videoBitRate: rates[.video] ?? 0, audioBitRate: rates[.audio] ?? 0, videoLength: videoLength, length: cuts.keptLength(in: range), speed: speed, muted: muted)
    }

    /// Every video frame is kept at any speed, so the video's size depends only on the source length it
    /// copies, `videoLength` (`length` when nil); the audio plays for `length / speed`.
    static func estimatedBytes(videoBitRate: Double, audioBitRate: Double, videoLength: Double? = nil, length: Double, speed: Double, muted: Bool) -> Int {
        let audio = muted ? 0 : audioBitRate * length / speed
        return Int(((videoBitRate * (videoLength ?? length) + audio) / 8).rounded())
    }

    /// Seconds of video a passthrough copy of `kept` writes. Frames depend on the sync frame before
    /// them, so each section reaches back to its entry in `syncTimes`.
    static func copiedLength(of kept: [TrimRange], syncTimes: [Double]) -> Double {
        zip(kept, syncTimes).reduce(0) { $0 + $1.0.end - min($1.1, $1.0.start) }
    }

    /// When the sync frame at or before `time` is shown.
    private static func syncTime(atOrBefore time: Double, in track: AVAssetTrack) -> Double {
        guard let cursor = track.makeSampleCursor(presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 600)) else {
            return time
        }
        while !cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue, cursor.stepInPresentationOrder(byCount: -1) == -1 {}
        return cursor.presentationTimeStamp.seconds
    }

    private static func fileType(of url: URL) throws -> AVFileType {
        guard let identifier = UTType(filenameExtension: url.pathExtension)?.identifier else {
            throw TrimError.unsupportedFileType
        }
        return AVFileType(rawValue: identifier)
    }

    /// The `kept` sections of the video tracks and of `audio`, end to end and retimed by `speed`.
    private static func composition(of asset: AVURLAsset, kept: [TrimRange], audio: [AVAssetTrack], speed: Double) async throws -> AVMutableComposition {
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
    private static func retime(_ asset: AVURLAsset, audio: [AVAssetTrack], range: TrimRange, cuts: CutList, speed: Double, to output: URL, as fileType: AVFileType) async throws -> Bool {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("Shot/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let videoURL = scratch.appendingPathComponent("video.mp4")
        let passthrough = try await trim(asset.url, range: range, cuts: cuts, speed: speed, muted: true, to: videoURL, as: .mp4)

        let retimed = AVMutableComposition()
        for track in audio {
            try insert(cuts.kept(in: range), of: track, into: retimed, speed: speed)
        }
        guard let export = AVAssetExportSession(asset: retimed, presetName: AVAssetExportPresetAppleM4A) else {
            throw TrimError.exportFailed
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
    private static func mux(video: URL, audio: URL, to output: URL, as fileType: AVFileType) async throws {
        let writer = try AVAssetWriter(outputURL: output, fileType: fileType)
        let videoAsset = AVURLAsset(url: video)
        let duration = try await videoAsset.load(.duration)
        var copies: [(reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)] = []
        for (asset, type) in [(videoAsset, AVMediaType.video), (AVURLAsset(url: audio), .audio)] {
            guard let track = try await asset.loadTracks(withMediaType: type).first else {
                throw TrimError.exportFailed
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
            throw writer.error ?? TrimError.exportFailed
        }
        writer.startSession(atSourceTime: .zero)
        do {
            for copy in copies where !copy.reader.startReading() {
                throw copy.reader.error ?? TrimError.exportFailed
            }
            // Reading a sample blocks until it's decoded, so the copy runs on a queue of its own rather than
            // holding one of Swift's few cooperative threads, which the readers' other work may be waiting for.
            nonisolated(unsafe) let (pending, sharedWriter) = (copies, writer)
            let cancelled = OSAllocatedUnfairLock(initialState: false)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue(label: "Shot.mux").async {
                        continuation.resume(with: Result {
                            try copySamples(pending, into: sharedWriter) { cancelled.withLock { $0 } }
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
            throw writer.error ?? TrimError.exportFailed
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
                        throw writer.error ?? TrimError.exportFailed
                    }
                    appended = true
                } else {
                    if copies[index].reader.status == .failed {
                        throw copies[index].reader.error ?? TrimError.exportFailed
                    }
                    copies[index].input.markAsFinished()
                    copies.remove(at: index)
                }
            }
            if !appended {
                // A writer that has stopped never takes more data, so waiting for it would never end.
                guard writer.status == .writing else {
                    throw writer.error ?? TrimError.exportFailed
                }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }

    /// Inserts the `kept` sections of `track` end to end at the start of `composition`, playing them at `speed`.
    @discardableResult
    private static func insert(_ kept: [TrimRange], of track: AVAssetTrack, into composition: AVMutableComposition, speed: Double) throws -> AVMutableCompositionTrack {
        guard let copy = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw TrimError.exportFailed
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
}
#endif
