import AVFoundation
import CoreGraphics
import Foundation

/// Reads video and audio files: what they hold, their frames and their sound, through AVFoundation's assets, image
/// generator and asset reader. It reports facts and leaves the decisions to its callers, such as `MediaProbe`,
/// `KeyFrameExtractor`, `Waveform`, `VideoTrimmer`'s estimate and `GIFExporter`.
public enum AVVideoReader {

    /// How long `url` plays, the size of its first video track's picture as it plays (`nil` without one), and whether it
    /// has sound, as the file says, unchecked. Throws when the file can't be read.
    public static func info(of url: URL) async throws -> ImportedMedia {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        var size: CGSize?
        if let track = video.first {
            let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
            let shown = natural.applying(transform)
            size = CGSize(width: abs(shown.width), height: abs(shown.height))
        }
        return ImportedMedia(source: url, duration: duration, size: size, hasAudio: !audio.isEmpty)
    }

    /// The average bit rates of `url`'s video tracks and of its audio tracks, each summed, in bits a second.
    public static func bitRates(of url: URL) async throws -> (video: Double, audio: Double) {
        let asset = AVURLAsset(url: url)
        var rates: [AVMediaType: Double] = [:]
        for type in [AVMediaType.video, .audio] {
            for track in try await asset.loadTracks(withMediaType: type) {
                rates[type, default: 0] += Double(try await track.load(.estimatedDataRate))
            }
        }
        return (rates[.video] ?? 0, rates[.audio] ?? 0)
    }

    /// When the sync frame at or before each of `times` is shown in `url`'s first video track, or the time itself where
    /// the file can't say; `nil` when it has no video or can't find sync frames at all.
    public static func syncTimes(atOrBefore times: [Double], in url: URL) async throws -> [Double]? {
        guard let video = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first, try await video.load(.canProvideSampleCursors) else {
            return nil
        }
        return times.map { syncTime(atOrBefore: $0, in: video) }
    }

    /// When the sync frame at or before `time` is shown.
    private static func syncTime(atOrBefore time: Double, in track: AVAssetTrack) -> Double {
        guard let cursor = track.makeSampleCursor(presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 600)) else {
            return time
        }
        while !cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue, cursor.stepInPresentationOrder(byCount: -1) == -1 {}
        return cursor.presentationTimeStamp.seconds
    }

    /// Decodes the frames of `url` at `times`, upright, at most `maxSize` (0 leaves that side free) and never enlarged,
    /// and hands each to `body` in the order of `times`. A frame may come from up to `tolerance` seconds either side of its
    /// time; `nil` lets the reader pick whatever's quickest.
    public static func readFrames(of url: URL, at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws {
        try await Self.readFrames(of: AVURLAsset(url: url), at: times, maxSize: maxSize, tolerance: tolerance, body)
    }

    /// Decodes `asset`'s frames at `times` as `readFrames(of:)` does, drawn by `videoComposition` when there is one.
    static func readFrames(
        of asset: AVAsset, drawnBy videoComposition: AVVideoComposition? = nil, at times: [Double], maxSize: CGSize, tolerance: Double?,
        _ body: (VideoFrame) throws -> Void
    ) async throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        if let tolerance {
            let tolerance = CMTime(seconds: tolerance, preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
        }
        let requested = times.map { CMTime(seconds: $0, preferredTimescale: 600) }
        // Each result names its time as a CMTime, rounded to the timescale; find which of `times` it answers, the first
        // still waiting when two round alike.
        var waiting: [CMTime: [Int]] = [:]
        for (index, time) in requested.enumerated() {
            waiting[time, default: []].append(index)
        }
        // `images(for:)` doesn't promise order, so a frame that comes early waits for the ones before it.
        var early: [Int: VideoFrame] = [:]
        var next = 0
        for await result in generator.images(for: requested) {
            guard let index = waiting[result.requestedTime]?.first else {
                continue
            }
            waiting[result.requestedTime]?.removeFirst()
            let decoded = Result { () throws -> (time: Double, image: PlatformImage) in
                let image = try result.image
                return ((try? result.actualTime.seconds) ?? times[index], image)
            }
            early[index] = VideoFrame(requestedTime: times[index], decoded: decoded)
            while let frame = early.removeValue(forKey: next) {
                try body(frame)
                next += 1
            }
        }
        try Task.checkCancellation()
        // Any left had a frame before them that never came.
        for (_, frame) in early.sorted(by: { $0.key < $1.key }) {
            try body(frame)
        }
    }

    /// Decodes `url`'s first audio track as mono 32-bit float samples at `sampleRate`, handing them to `body` in order, a
    /// chunk at a time. Reading may block the calling thread until each chunk is decoded.
    public static func readMonoSamples(of url: URL, sampleRate: Double, _ body: ([Float]) throws -> Void) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else {
                continue
            }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            try body(data)
        }
        if reader.status == .failed {
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }
    }
}
