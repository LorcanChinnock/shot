import CoreGraphics
import Foundation
import Vision
import os

private let log = Logger.shot("text")

/// Vision blocks the thread a read runs on while it waits for work of its own, so reads at once can take every thread
/// Swift's concurrency has on a Mac with few cores, and never finish: CI's 3-core virtual machine hung that way.
private let reads = Turns()

private actor Turns {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func oneAtATime<T: Sendable>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        while busy {
            await withCheckedContinuation { waiting.append($0) }
        }
        busy = true
        defer {
            busy = false
            if !waiting.isEmpty {
                waiting.removeFirst().resume()
            }
        }
        return try await work()
    }
}

/// Reads the text in an image with Vision, on the device: nothing leaves the Mac. Boxes come back in the image's
/// pixels with a top-left origin, rounded out to whole pixels, so they line up with the marks in a capture's record
/// and hiding one covers all of its text.
public enum TextRecognizer {
    public static func recognize(_ image: CGImage) async throws -> CaptureText {
        do {
            return try await recognize(image, level: .accurate)
        } catch is CancellationError {
            throw CancellationError()
        } catch let accurateError {
            // The accurate model can't run everywhere: in a macOS 27 virtual machine, with no Neural Engine, it fails to
            // compile on every device. The fast one still reads screen text, which is clean.
            log.error("Accurate text recognition failed, so reading with the fast one: \(accurateError, privacy: .public)")
            do {
                return try await recognize(image, level: .fast)
            } catch {
                throw accurateError
            }
        }
    }

    /// The text in `image`, read at `level` alone.
    static func recognize(_ image: CGImage, level: RecognizeTextRequest.RecognitionLevel) async throws -> CaptureText {
        let observations = try await reads.oneAtATime {
            var request = RecognizeTextRequest()
            request.recognitionLevel = level
            return try await request.perform(on: image)
        }
        let size = CGSize(width: image.width, height: image.height)
        let bounds = CGRect(origin: .zero, size: size)
        func pixels(_ rect: NormalizedRect) -> CGRect {
            rect.toImageCoordinates(size, origin: .upperLeft).integral.intersection(bounds)
        }
        let lines = observations.compactMap { observation -> CaptureText.Line? in
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let text = candidate.string
            let box = pixels(observation.boundingBox)
            let words = CaptureText.Line.wordRanges(in: text).map { range in
                CaptureText.Word(text: String(text[range]), box: candidate.boundingBox(for: range).map { pixels($0.boundingBox) } ?? box)
            }
            return CaptureText.Line(text: text, box: box, confidence: Double(candidate.confidence), words: words)
        }
        return CaptureText(width: image.width, height: image.height, lines: CaptureText.readingOrder(lines))
    }

    /// The text in the image file at `url`, or `nil` when it isn't an image. A GIF's first frame.
    public static func recognize(fileAt url: URL) async throws -> CaptureText? {
        guard let image = ImageCodec.image(at: url) else {
            return nil
        }
        return try await recognize(image)
    }
}
