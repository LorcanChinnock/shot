import CoreGraphics
import Foundation

/// Pulls still frames out of a video for an agent, which can't watch one: samples it a few times a second as tiny
/// grayscale thumbnails to find where the picture changes (`FramePicker` does the picking), then decodes
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
        let sampled = try await differences(in: url, duration: duration)
        return FramePicker.pick(differences: sampled.differences, times: sampled.times, count: count).map { sampled.actual[$0] }
    }

    /// The times sampled through the video at `url`, which is `duration` long, how much each differs from the one before
    /// (0 for the first), and the time of the frame each one actually read.
    public static func differences(in url: URL, duration: Double) async throws -> (times: [Double], differences: [Double], actual: [Double]) {
        let samples = min(maximumSamples, max(2, Int(duration * sampleRate) + 1))
        let last = max(0, duration - 0.05)
        let times = (0 ..< samples).map { last * Double($0) / Double(samples - 1) }
        var thumbnails: [Double: [UInt8]] = [:]
        var actual: [Double: Double] = [:]
        try await AVVideoReader.readFrames(of: url, at: times, maxSize: CGSize(width: 160, height: 160), tolerance: last / Double(samples - 1) / 2) { frame in
            try Task.checkCancellation()
            // A frame that won't decode counts as no change rather than failing the whole video.
            if let (time, image) = try? frame.decoded.get() {
                thumbnails[frame.requestedTime] = gray(image)
                actual[frame.requestedTime] = time
            }
        }
        var differences = [0.0]
        for (previous, next) in zip(times, times.dropFirst()) {
            differences.append(thumbnails[previous].flatMap { a in thumbnails[next].map { FramePicker.difference(a, $0) } } ?? 0)
        }
        return (times, differences, times.map { actual[$0] ?? $0 })
    }

    /// The frames at `times`, at most `maxWidth` wide and never enlarged, decoded exactly there.
    public static func frames(of url: URL, at times: [Double], maxWidth: Int) async throws -> [Frame] {
        var frames: [Frame] = []
        try await AVVideoReader.readFrames(of: url, at: times, maxSize: CGSize(width: maxWidth, height: 0), tolerance: 0) { frame in
            try Task.checkCancellation()
            let (time, image) = try frame.decoded.get()
            frames.append(Frame(time: time, image: image))
        }
        return frames.sorted { $0.time < $1.time }
    }

    /// `image` drawn small into a grey bitmap, as bytes.
    public static func gray(_ image: CGImage) -> [UInt8] {
        let (width, height) = thumbnailSize
        guard let canvas = CGContext.bitmap(width: width, height: height, format: .grey) else {
            return [UInt8](repeating: 0, count: width * height)
        }
        canvas.interpolationQuality = .low
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bitmap = canvas.makeBitmap() else {
            return [UInt8](repeating: 0, count: width * height)
        }
        // A grey canvas reads back with the same level in red, green and blue.
        return stride(from: 0, to: bitmap.pixels.count, by: 4).map { bitmap.pixels[bitmap.pixels.startIndex + $0] }
    }
}
