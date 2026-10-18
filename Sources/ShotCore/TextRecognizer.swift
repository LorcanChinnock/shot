#if canImport(CoreGraphics) && canImport(Vision)
import CoreGraphics
import Foundation
import Vision

/// Reads the text in an image with Vision, on the device: nothing leaves the Mac. Boxes come back in the image's
/// pixels with a top-left origin, rounded out to whole pixels, so they line up with the marks in a capture's record
/// and hiding one covers all of its text.
public enum TextRecognizer {
    public static func recognize(_ image: CGImage) async throws -> CaptureText {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        let observations = try await request.perform(on: image)
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
    public static func recognize(fileAt url: URL, codec: any ImageCoding) async throws -> CaptureText? {
        guard let image = codec.image(at: url) else {
            return nil
        }
        return try await recognize(image)
    }
}
#endif
