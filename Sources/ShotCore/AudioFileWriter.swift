import AVFoundation

/// Writes one live audio source to its own AAC file, which starts at the time given to `start(at:)`.
/// Samples arrive on a capture queue and `finish` on another, so `lock` guards every stored property.
public final class AudioFileWriter: @unchecked Sendable {
    public enum WriteError: LocalizedError {
        case unsupportedFormat
        case cannotAddInput
        case cannotStart

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat: "The audio's format can't be written"
            case .cannotAddInput: "Could not add the audio to its file"
            case .cannotStart: "Could not start writing the audio file"
            }
        }
    }

    public let url: URL
    private let lock = NSLock()
    private var origin: CMTime?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var finished = false
    private var _failure: Error?

    /// Why the file couldn't be written, so it's missing or incomplete; `nil` while all is well. A source that never
    /// sent a sample isn't a failure.
    public var failure: Error? {
        lock.withLock { _failure }
    }

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
        guard let writer else {
            return
        }
        guard writer.status == .writing else {
            if writer.status == .failed {
                fail(writer.error ?? WriteError.cannotStart)
            }
            return
        }
        input?.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            fail(writer.error ?? WriteError.cannotStart)
        }
    }

    private func fail(_ error: Error) {
        lock.withLock {
            _failure = _failure ?? error
        }
    }

    /// Called with `lock` held.
    private func open(format: CMFormatDescription?, at origin: CMTime) {
        guard let source = format?.audioStreamBasicDescription else {
            finished = true
            _failure = WriteError.unsupportedFormat
            return
        }
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            finished = true
            _failure = error
            return
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: source.mSampleRate, AVNumberOfChannelsKey: min(source.mChannelsPerFrame, 2),
        ], sourceFormatHint: format)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            finished = true
            _failure = WriteError.cannotAddInput
            return
        }
        writer.add(input)
        guard writer.startWriting() else {
            finished = true
            _failure = writer.error ?? WriteError.cannotStart
            return
        }
        writer.startSession(atSourceTime: origin)
        self.writer = writer
        self.input = input
    }
}
