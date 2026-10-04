import AVFoundation
import os
import UniformTypeIdentifiers

public enum TrimHandle: Sendable {
    case start, end
}

/// The part of a recording to keep, in seconds.
public struct TrimRange: Equatable, Sendable {
    /// Shortest range the handles can make, so they never cross.
    public static let minimumLength: Double = 0.1

    public private(set) var start: Double
    public private(set) var end: Double

    public init(duration: Double) {
        start = 0
        end = max(0, duration)
    }

    /// Clamps to `0...duration` and orders the ends.
    public init(start: Double, end: Double, duration: Double) {
        let clamped = [start, end].map { min(max($0, 0), max(0, duration)) }
        self.start = clamped.min()!
        self.end = clamped.max()!
    }

    public var length: Double { end - start }

    public var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
    }

    public func isFull(duration: Double) -> Bool {
        start <= 0 && end >= duration
    }

    /// Drags `handle` to `time`, keeping the range inside the video and at least `minimumLength` long.
    public func moving(_ handle: TrimHandle, to time: Double, duration: Double) -> TrimRange {
        guard duration > Self.minimumLength else {
            return self
        }
        var moved = self
        switch handle {
        case .start:
            moved.start = min(max(time, 0), end - Self.minimumLength)
        case .end:
            moved.end = max(min(time, duration), start + Self.minimumLength)
        }
        return moved
    }

    /// Where Play begins: the playhead if it's inside the range, otherwise the in point.
    /// Within `endTolerance` of the out point counts as finished, since playback can stop a hair short of it.
    public func playbackStart(from current: Double, endTolerance: Double = 0.01) -> Double {
        current >= start && current < end - endTolerance ? current : start
    }
}

public enum Timecode {
    /// `m:ss.cc`, rounding down so the out point never reads past the end.
    public static func string(_ seconds: Double) -> String {
        let hundredths = Int((max(0, seconds) * 100).rounded(.down))
        let minutes = hundredths / 6000
        let secs = hundredths / 100 % 60
        return "\(minutes):" + String(format: "%02d.%02d", secs, hundredths % 100)
    }
}

/// Maps a recording's time onto a horizontal strip of `width` points starting at `minX`.
/// The start handle sits left of the in point and the end handle right of the out point.
public struct TrimTimeline: Sendable {
    public static let handleWidth: CGFloat = 12
    /// Extra reach around a handle, so a thin one is still easy to grab.
    public static let slop: CGFloat = 4

    public let duration: Double
    public let minX: CGFloat
    public let width: CGFloat

    public init(duration: Double, minX: CGFloat, width: CGFloat) {
        self.duration = duration
        self.minX = minX
        self.width = width
    }

    public func x(for time: Double) -> CGFloat {
        guard duration > 0 else {
            return minX
        }
        return minX + width * CGFloat(min(max(time, 0), duration) / duration)
    }

    public func time(at x: CGFloat) -> Double {
        guard width > 0 else {
            return 0
        }
        return duration * Double(min(max((x - minX) / width, 0), 1))
    }

    /// The handle under `x`, the nearer one when both are in reach.
    public func handle(at x: CGFloat, range: TrimRange) -> TrimHandle? {
        let startX = self.x(for: range.start), endX = self.x(for: range.end)
        let toStart = distance(from: x, to: startX - Self.handleWidth...startX)
        let toEnd = distance(from: x, to: endX...endX + Self.handleWidth)
        guard min(toStart, toEnd) <= Self.slop else {
            return nil
        }
        return toStart <= toEnd ? .start : .end
    }

    private func distance(from x: CGFloat, to span: ClosedRange<CGFloat>) -> CGFloat {
        x < span.lowerBound ? span.lowerBound - x : max(0, x - span.upperBound)
    }

    /// How many frames of `aspectRatio` (width / height) it takes to fill the strip.
    public static func thumbnailCount(width: CGFloat, height: CGFloat, aspectRatio: CGFloat) -> Int {
        let frameWidth = height * aspectRatio
        guard frameWidth > 0 else {
            return 1
        }
        return max(1, Int((width / frameWidth).rounded(.up)))
    }

    /// The midpoint of each of `count` equal slots.
    public func thumbnailTimes(count: Int) -> [Double] {
        (0..<max(1, count)).map { duration * (Double($0) + 0.5) / Double(max(1, count)) }
    }
}

/// Which editor a file opens in: `shot://annotate` picks by file type, `shot://edit-video` always uses the video editor.
public enum EditorRoute: Equatable, Sendable {
    case image(URL)
    case video(URL)

    public static let hosts: Set<String> = ["annotate", "edit-video"]

    public init?(host: String, path: String?) {
        guard Self.hosts.contains(host), let path, !path.isEmpty else {
            return nil
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        self = host == "edit-video" ? .video(url) : EditorRoute(fileURL: url)
    }

    public init(fileURL: URL) {
        let isVideo = UTType(filenameExtension: fileURL.pathExtension)?.conforms(to: .movie) == true
        self = isVideo ? .video(fileURL) : .image(fileURL)
    }
}

public enum VideoTrimmer {
    public enum TrimError: LocalizedError {
        case unsupportedFileType
        case exportFailed
        case nothingLeft

        public var errorDescription: String? {
            switch self {
            case .unsupportedFileType: "Can't write this kind of video"
            case .exportFailed: "Could not export the trimmed video"
            case .nothingLeft: "The cuts leave nothing to export"
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
