import CoreGraphics
import Foundation
import Vision

/// How auto-redact hides what it finds.
public enum RedactionStyle: Sendable {
    case blur, pixelate

    func kind(_ rect: CGRect) -> Annotation.Kind {
        switch self {
        case .blur: .blur(rect)
        case .pixelate: .pixelate(rect)
        }
    }
}

/// Finds text worth hiding (email addresses, phone numbers, card numbers, IP addresses) so the editor can
/// cover it. It only locates the text; nothing it reads leaves this type.
public enum Redaction {
    private static let patterns: [NSRegularExpression] = [
        // Email addresses.
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        // Card-like numbers: 13 to 19 digits, optionally grouped with spaces or dashes.
        #"(?<![\d.])\d(?:[ -]?\d){12,18}(?![\d.])"#,
        // IPv4 addresses.
        #"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\d.])"#,
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    private static let phoneDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)

    /// The parts of `string` that look sensitive, in order, with overlapping matches merged.
    public static func sensitiveRanges(in string: String) -> [Range<String.Index>] {
        let whole = NSRange(string.startIndex..., in: string)
        let found = (patterns + [phoneDetector])
            .flatMap { $0.matches(in: string, range: whole) }
            .compactMap { Range($0.range, in: string) }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in found where !range.isEmpty {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Regions of `image` that hold sensitive text, in image pixels with a top-left origin.
    /// Text recognition is slow, so call it off the main thread.
    public static func regions(in image: CGImage) throws -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Correction "fixes" addresses and digit runs into words, so read the text as it is.
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let size = CGSize(width: image.width, height: image.height)
        return (request.results ?? []).flatMap { observation -> [CGRect] in
            guard let candidate = observation.topCandidates(1).first else {
                return []
            }
            return sensitiveRanges(in: candidate.string).compactMap { range in
                (try? candidate.boundingBox(for: range)).map { imageRect(forNormalizedBox: $0.boundingBox, imageSize: size) }
            }
        }
    }

    /// Converts a Vision box (normalised, bottom-left origin) to whole image pixels with a top-left origin,
    /// with a margin so the tops and tails of the letters are covered too.
    static func imageRect(forNormalizedBox box: CGRect, imageSize: CGSize) -> CGRect {
        let rect = CGRect(x: box.minX * imageSize.width, y: (1 - box.maxY) * imageSize.height, width: box.width * imageSize.width, height: box.height * imageSize.height)
        let margin = max(2, rect.height * 0.2)
        return rect.insetBy(dx: -margin, dy: -margin).integral
    }
}

extension EditorDocument {
    /// A blur or pixelate annotation for each of `regions` that's on the canvas and not already under one.
    public func redactions(covering regions: [CGRect], style: RedactionStyle, color: RGBA, lineWidth: CGFloat) -> [Annotation] {
        var hidden = annotations.compactMap { annotation -> CGRect? in
            switch annotation.kind {
            case let .blur(rect), let .pixelate(rect): rect
            default: nil
            }
        }
        var added: [Annotation] = []
        for region in regions where region.intersects(canvasRect) && !hidden.contains(where: { $0.contains(region) }) {
            added.append(Annotation(kind: style.kind(region), color: color, lineWidth: lineWidth))
            hidden.append(region)
        }
        return added
    }
}
