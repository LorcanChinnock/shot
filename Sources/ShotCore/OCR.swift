import CoreGraphics
import Vision

public enum OCR {
    /// Returns recognized lines in reading order, joined with newlines.
    public static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = (request.results ?? []).sorted { a, b in
            // Vision uses a bottom-left origin; same-line boxes overlap vertically.
            if abs(a.boundingBox.midY - b.boundingBox.midY) < min(a.boundingBox.height, b.boundingBox.height) / 2 {
                return a.boundingBox.minX < b.boundingBox.minX
            }
            return a.boundingBox.midY > b.boundingBox.midY
        }
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
