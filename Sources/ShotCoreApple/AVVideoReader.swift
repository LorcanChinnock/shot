import AVFoundation
import CoreGraphics
import Foundation

/// The Mac's `VideoReader`: AVFoundation's assets, image generator and asset reader.
public struct AVVideoReader: VideoReader {
    public init() {}

    public func info(of url: URL) async throws -> ImportedMedia {
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

    public func bitRates(of url: URL) async throws -> (video: Double, audio: Double) {
        let asset = AVURLAsset(url: url)
        var rates: [AVMediaType: Double] = [:]
        for type in [AVMediaType.video, .audio] {
            for track in try await asset.loadTracks(withMediaType: type) {
                rates[type, default: 0] += Double(try await track.load(.estimatedDataRate))
            }
        }
        return (rates[.video] ?? 0, rates[.audio] ?? 0)
    }

    public func syncTimes(atOrBefore times: [Double], in url: URL) async throws -> [Double]? {
        guard let video = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first, try await video.load(.canProvideSampleCursors) else {
            return nil
        }
        return times.map { syncTime(atOrBefore: $0, in: video) }
    }

    /// When the sync frame at or before `time` is shown.
    private func syncTime(atOrBefore time: Double, in track: AVAssetTrack) -> Double {
        guard let cursor = track.makeSampleCursor(presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 600)) else {
            return time
        }
        while !cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue, cursor.stepInPresentationOrder(byCount: -1) == -1 {}
        return cursor.presentationTimeStamp.seconds
    }

    public func readFrames(of url: URL, at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        if let tolerance {
            let tolerance = CMTime(seconds: tolerance, preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
        }
        let requested = times.map { CMTime(seconds: $0, preferredTimescale: 600) }
        // Each result names its time as a CMTime, rounded to the timescale; hand back the time as it was asked for.
        let asked = Dictionary(zip(requested, times), uniquingKeysWith: { first, _ in first })
        for await result in generator.images(for: requested) {
            let time = asked[result.requestedTime] ?? result.requestedTime.seconds
            let decoded = Result { () throws -> (time: Double, image: PlatformImage) in
                let image = try result.image
                return ((try? result.actualTime.seconds) ?? time, image)
            }
            try body(VideoFrame(requestedTime: time, decoded: decoded))
        }
    }

    public func readMonoSamples(of url: URL, sampleRate: Double, _ body: ([Float]) throws -> Void) async throws {
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
