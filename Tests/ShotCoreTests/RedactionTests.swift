import CoreGraphics
import CoreText
import Foundation
import Testing
import Vision
@testable import ShotCore

private let lineTop: CGFloat = 20
private let lineSpacing: CGFloat = 60
private let fontSize: CGFloat = 28

/// Black text on white, one line every `lineSpacing` px from `lineTop`.
private func textImage(_ lines: [String], width: Int = 900) throws -> CGImage {
    let height = Int(lineTop * 2 + lineSpacing * CGFloat(lines.count))
    let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (index, string) in lines.enumerated() {
        let layout = TextLayout(string: string, fontSize: fontSize, color: RGBA(0, 0, 0))
        ctx.textPosition = CGPoint(x: 20, y: CGFloat(height) - (band(index).minY + layout.ascent))
        CTLineDraw(try #require(layout.lines.first), ctx)
    }
    return try #require(ctx.makeImage())
}

/// Line `index`'s strip of the image, top-left origin.
private func band(_ index: Int) -> CGRect {
    CGRect(x: 0, y: lineTop + lineSpacing * CGFloat(index), width: 10_000, height: lineSpacing)
}

/// Where `prefix` ends as drawn by `textImage`: its width plus the left margin.
private func textEnd(_ prefix: String) -> CGFloat {
    20 + TextLayout(string: prefix, fontSize: fontSize, color: RGBA(0, 0, 0)).size.width
}

private func matches(_ string: String) -> [String] {
    Redaction.sensitiveRanges(in: string).map { String(string[$0]) }
}

// MARK: Finding sensitive text

@Test func findsEmailsPhonesCardsAndAddresses() {
    #expect(matches("Mail jane.doe@example.com today") == ["jane.doe@example.com"])
    #expect(matches("Call +1 (415) 555-0132 now").map { $0.trimmingCharacters(in: .whitespaces) } == ["+1 (415) 555-0132"])
    #expect(matches("Card 4111 1111 1111 1111 exp") == ["4111 1111 1111 1111"])
    #expect(matches("Card 5500-0000-0000-0004") == ["5500-0000-0000-0004"])
    #expect(matches("Host 192.168.10.24 up") == ["192.168.10.24"])
}

@Test func findsNumbersThatEndASentence() {
    #expect(matches("Charged to 4111 1111 1111 1111.") == ["4111 1111 1111 1111"])
    #expect(matches("Server is 10.0.0.1.") == ["10.0.0.1"])
    #expect(matches("See 1.10.0.0.1 for details").isEmpty)
}

@Test func ignoresOrdinaryText() {
    #expect(matches("Nothing secret on this line").isEmpty)
    #expect(matches("Version 2.4 shipped with 12 fixes").isEmpty)
    #expect(matches("Not an address: 999.1.1.1").isEmpty)
    #expect(matches("").isEmpty)
}

@Test func overlappingMatchesMerge() {
    // A long digit run can read as both a phone number and a card number; it's one region.
    let string = "Ref 4111 1111 1111 1111"
    let ranges = Redaction.sensitiveRanges(in: string)
    #expect(ranges.count == 1)
    #expect(ranges.allSatisfy { !$0.isEmpty })
    let two = Redaction.sensitiveRanges(in: "a@b.co and c@d.co")
    #expect(two.count == 2)
}

// MARK: Geometry

@Test func visionBoxesBecomeTopLeftImageRectsWithAMargin() {
    // Vision's box is normalised with a bottom-left origin.
    let box = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.1)
    let rect = Redaction.imageRect(forNormalizedBox: box, imageSize: CGSize(width: 400, height: 200))
    // 100...300 across and 80...100 down, before the margin.
    #expect(rect.contains(CGRect(x: 100, y: 80, width: 200, height: 20)))
    #expect(rect.minX < 100 && rect.maxY > 100)
    #expect(rect.width < 220 && rect.height < 40)
    #expect(rect == rect.integral)
}

@Test func redactionsSkipRegionsOffTheCanvasOrAlreadyHidden() {
    var doc = EditorDocument(base: solidImage(width: 400, height: 200))
    doc.annotations.append(Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: 120, height: 60)), color: RGBA.presets[0], lineWidth: 4))
    doc.crop(to: CGRect(x: 0, y: 0, width: 300, height: 200))
    let covered = CGRect(x: 10, y: 10, width: 50, height: 20)
    let cropped = CGRect(x: 320, y: 10, width: 50, height: 20)
    let fresh = CGRect(x: 150, y: 100, width: 80, height: 20)
    let blurs = doc.redactions(covering: [covered, cropped, fresh], style: .blur, color: RGBA.presets[0], lineWidth: 4)
    #expect(blurs.map(\.kind) == [.blur(fresh)])
    let pixelates = doc.redactions(covering: [fresh, fresh], style: .pixelate, color: RGBA.presets[0], lineWidth: 4)
    #expect(pixelates.map(\.kind) == [.pixelate(fresh)])
}

// MARK: Detecting in an image

private let sample = [
    "Email: jane.doe@example.com",
    "Phone: +1 (415) 555-0132",
    "Card: 4111 1111 1111 1111",
    "Server: 192.168.10.24",
    "Nothing secret on this line",
]

// Vision's text recognizer can deadlock when requests run at once on a machine with few cores, as CI's
// runners have, so these tests run one at a time.
@Suite(.serialized) struct TextRecognitionTests {
    @Test func autoRedactFindsTheSampleStrings() async throws {
        let image = try textImage(sample)
        let regions = try await Redaction.regions(in: image)
        #expect(regions.count == 4)
        for (index, label) in ["Email", "Phone", "Card", "Server"].enumerated() {
            let onLine = regions.filter { band(index).contains(CGPoint(x: $0.midX, y: $0.midY)) }
            #expect(onLine.count == 1, "line \(index)")
            guard let region = onLine.first else {
                continue
            }
            // It covers the whole value. Vision's boxes for part of a line are loose, so it may take the
            // colon too, but the label's word stays readable.
            #expect(region.minX <= textEnd(label + ": ") + 2, "line \(index)")
            #expect(region.maxX >= textEnd(sample[index]) - 2, "line \(index)")
            #expect(region.minX > textEnd(label) - 4, "line \(index)")
        }
        #expect(!regions.contains { band(4).contains(CGPoint(x: $0.midX, y: $0.midY)) })
    }

    @Test(arguments: [RedactionStyle.blur, .pixelate])
    func redactedTextCantBeReadBack(style: RedactionStyle) async throws {
        let image = try textImage(sample)
        var doc = EditorDocument(base: image)
        doc.annotations += doc.redactions(covering: try await Redaction.regions(in: image), style: style, color: RGBA.presets[0], lineWidth: 4)
        let exported = try #require(AnnotationRenderer.flatten(doc))
        #expect(try await Redaction.regions(in: exported).isEmpty)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: exported).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        for secret in ["jane", "example", "415", "0132", "4111", "192", "168"] {
            #expect(!text.contains(secret), "\(secret) in \(text)")
        }
        // The labels and the clean line survive.
        #expect(text.contains("Nothing secret"))
    }
}
