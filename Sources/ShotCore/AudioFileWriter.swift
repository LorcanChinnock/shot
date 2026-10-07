import AVFoundation

/// Writes one live audio source to its own AAC file, which starts at the time given to `start(at:)`.
public final class AudioFileWriter: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private var origin: CMTime?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var finished = false

    public init(url: URL) {
        self.url = url
    }

    /// Samples ending before `time` are dropped; only the first call counts.
    public func start(at time: CMTime) {
        lock.withLock {
            if origin == nil {
                origin = time
            }
        }
    }

    public func append(_ buffer: CMSampleBuffer) {
        lock.withLock {
            guard !finished, let origin else {
                return
            }
            let end = buffer.duration.isNumeric ? buffer.presentationTimeStamp + buffer.duration : buffer.presentationTimeStamp
            guard end > origin || buffer.presentationTimeStamp == origin else {
                return
            }
            if writer == nil {
                open(format: buffer.formatDescription, at: origin)
            }
            guard let input, input.isReadyForMoreMediaData else {
                return
            }
            input.append(buffer)
        }
    }

    /// Later samples are dropped. Safe to call more than once.
    public func finish() async {
        let (writer, input) = lock.withLock {
            finished = true
            defer {
                self.writer = nil
                self.input = nil
            }
            return (self.writer, self.input)
        }
        guard let writer, writer.status == .writing else {
            return
        }
        input?.markAsFinished()
        await writer.finishWriting()
    }

    private func open(format: CMFormatDescription?, at origin: CMTime) {
        guard let source = format?.audioStreamBasicDescription, let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            finished = true
            return
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: source.mSampleRate, AVNumberOfChannelsKey: min(source.mChannelsPerFrame, 2),
        ], sourceFormatHint: format)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            finished = true
            return
        }
        writer.add(input)
        guard writer.startWriting() else {
            finished = true
            return
        }
        writer.startSession(atSourceTime: origin)
        self.writer = writer
        self.input = input
    }
}
