import AVFoundation
import CoreGraphics

/// Pulls still frames out of a video for an agent, which can't watch one: samples it a few times a second as tiny
/// grayscale thumbnails to find where the picture changes (ShotModel's `FramePicker` does the picking), then decodes
/// only the frames picked at full size.
public enum KeyFrameExtractor {
    public struct Frame: @unchecked Sendable {
        /// Seconds from the start, of the frame actually decoded.
        public let time: Double
        public let image: CGImage
    }

    /// Samples a second when looking for changes, and the most for a long video, which is then sampled less often.
    static let sampleRate = 4.0
    static let maximumSamples = 1200
    /// The thumbnails compared, small enough to ignore noise and fast to decode.
    static let thumbnailSize = (width: 64, height: 36)

    /// The times of the `count` frames that show what happens in the video at `url`, which is `duration` long.
    public static func changeTimes(in url: URL, duration: Double, count: Int) async throws -> [Double] {
        let samples = min(maximumSamples, max(2, Int(duration * sampleRate) + 1))
        let last = max(0, duration - 0.05)
        let times = (0 ..< samples).map { last * Double($0) / Double(samples - 1) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        let tolerance = CMTime(seconds: last / Double(samples - 1) / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        var thumbnails: [Double: [UInt8]] = [:]
        var actual: [Double: Double] = [:]
        for await result in generator.images(for: times.map { CMTime(seconds: $0, preferredTimescale: 600) }) {
            try Task.checkCancellation()
            // A frame that won't decode counts as no change rather than failing the whole video.
            if let image = try? result.image {
                thumbnails[result.requestedTime.seconds] = gray(image)
                actual[result.requestedTime.seconds] = (try? result.actualTime.seconds) ?? result.requestedTime.seconds
            }
        }
        let keys = times.map { CMTime(seconds: $0, preferredTimescale: 600).seconds }
        var differences = [0.0]
        for (previous, next) in zip(keys, keys.dropFirst()) {
            differences.append(thumbnails[previous].flatMap { a in thumbnails[next].map { FramePicker.difference(a, $0) } } ?? 0)
        }
        return FramePicker.pick(differences: differences, times: times, count: count).map { actual[keys[$0]] ?? times[$0] }
    }

    /// The frames at `times`, at most `maxWidth` wide and never enlarged, decoded exactly there.
    public static func frames(of url: URL, at times: [Double], maxWidth: Int) async throws -> [Frame] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: 0)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var frames: [Frame] = []
        for await result in generator.images(for: times.map { CMTime(seconds: $0, preferredTimescale: 600) }) {
            try Task.checkCancellation()
            frames.append(Frame(time: (try? result.actualTime.seconds) ?? result.requestedTime.seconds, image: try result.image))
        }
        return frames.sorted { $0.time < $1.time }
    }

    /// `image` drawn into a small grayscale bitmap, as bytes.
    static func gray(_ image: CGImage) -> [UInt8] {
        let (width, height) = thumbnailSize
        var bytes = [UInt8](repeating: 0, count: width * height)
        bytes.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return
            }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }
}
