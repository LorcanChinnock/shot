import AVFoundation

/// The loudest and quietest samples in one slice of audio, from -1 to 1.
public struct WaveformPeak: Equatable, Sendable {
    public var min: Float
    public var max: Float

    public init(min: Float, max: Float) {
        self.min = min
        self.max = max
    }
}

/// An audio file's shape as min/max peaks at a fixed resolution, merged down to whatever width is drawn.
public struct Waveform: Equatable, Sendable {
    public static let peaksPerSecond = 100

    public let peaks: [WaveformPeak]
    public let duration: Double

    public init(peaks: [WaveformPeak], duration: Double) {
        self.peaks = peaks
        self.duration = duration
    }

    /// `count` peaks covering `range` seconds, each the extremes of the stored peaks it spans.
    public func peaks(in range: Range<Double>, count: Int) -> [WaveformPeak] {
        guard count > 0, !peaks.isEmpty, range.upperBound > range.lowerBound else {
            return []
        }
        let perSecond = Double(peaks.count) / max(duration, .leastNonzeroMagnitude)
        return (0..<count).map { index in
            let from = range.lowerBound + (range.upperBound - range.lowerBound) * Double(index) / Double(count)
            let to = range.lowerBound + (range.upperBound - range.lowerBound) * Double(index + 1) / Double(count)
            let first = min(max(Int((from * perSecond).rounded(.down)), 0), peaks.count - 1)
            let last = min(max(Int((to * perSecond).rounded(.up)) - 1, first), peaks.count - 1)
            return peaks[first...last].reduce(WaveformPeak(min: 0, max: 0)) { WaveformPeak(min: min($0.min, $1.min), max: max($0.max, $1.max)) }
        }
    }

    /// Reduces `samples` (mono, `sampleRate` per second) to `peaksPerSecond` peaks per second.
    public static func peaks(of samples: some Sequence<Float>, sampleRate: Double) -> [WaveformPeak] {
        var reducer = PeakReducer(sampleRate: sampleRate)
        samples.forEach { reducer.add($0) }
        return reducer.finish()
    }

    /// Reads the first audio track of `url`; nil when there's none. Runs off the main thread.
    public static func load(_ url: URL) async throws -> Waveform? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }
        let duration = try await asset.load(.duration).seconds
        return try await Task.detached(priority: .utility) {
            let reader = try AVAssetReader(asset: asset)
            let sampleRate = 8000.0
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
            var reducer = PeakReducer(sampleRate: sampleRate)
            while let buffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let block = CMSampleBufferGetDataBuffer(buffer) else {
                    continue
                }
                let length = CMBlockBufferGetDataLength(block)
                var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
                data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
                data.forEach { reducer.add($0) }
            }
            if reader.status == .failed {
                throw reader.error ?? CocoaError(.fileReadUnknown)
            }
            return Waveform(peaks: reducer.finish(), duration: duration)
        }.value
    }
}

private struct PeakReducer {
    private let perPeak: Int
    private var peaks: [WaveformPeak] = []
    private var current = WaveformPeak(min: 0, max: 0)
    private var seen = 0

    init(sampleRate: Double) {
        perPeak = max(1, Int((sampleRate / Double(Waveform.peaksPerSecond)).rounded()))
    }

    mutating func add(_ sample: Float) {
        current.min = min(current.min, sample)
        current.max = max(current.max, sample)
        seen += 1
        if seen == perPeak {
            peaks.append(current)
            current = WaveformPeak(min: 0, max: 0)
            seen = 0
        }
    }

    mutating func finish() -> [WaveformPeak] {
        if seen > 0 {
            peaks.append(current)
        }
        return peaks
    }
}
