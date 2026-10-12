import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ShotCore

/// A white image with each line of text drawn in black at its point from the top left.
private func image(width: Int, height: Int, _ lines: [(text: String, x: CGFloat, top: CGFloat)], size: CGFloat = 28) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    for line in lines {
        let string = NSAttributedString(string: line.text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ])
        // CoreGraphics' origin is the bottom left, and a line draws up from its baseline.
        context.textPosition = CGPoint(x: line.x, y: CGFloat(height) - line.top - CTFontGetAscent(font))
        CTLineDraw(CTLineCreateWithAttributedString(string), context)
    }
    return try #require(context.makeImage())
}

@Test func textIsReadInReadingOrderWithBoxesFromTheTopLeft() async throws {
    let picture = try image(width: 800, height: 300, [
        ("Invoice settings", 40, 30),
        ("Billing email", 40, 150),
    ])
    let text = try await TextRecognizer.recognize(picture)
    #expect(text.width == 800 && text.height == 300)
    #expect(text.lines.map(\.text) == ["Invoice settings", "Billing email"])
    let first = try #require(text.lines.first)
    // Drawn 30 pixels from the top: a bottom-left origin would put it near the bottom.
    #expect(first.box.minY >= 20 && first.box.maxY <= 75)
    #expect(first.box.minX >= 30 && first.box.minX <= 50)
    #expect(first.confidence > 0.5)
    #expect(first.words.map(\.text) == ["Invoice", "settings"])
    let invoice = try #require(first.words.first?.box), settings = try #require(first.words.last?.box)
    #expect(invoice.maxX <= settings.minX + 2)
    #expect(first.box.contains(invoice) && first.box.contains(settings))
    #expect(invoice == invoice.integral)
}

@Test func sensitiveTextReadFromAnImageIsBoxedWhereItWasDrawn() async throws {
    let picture = try image(width: 900, height: 200, [("Contact jane@example.com today", 40, 80)])
    let text = try await TextRecognizer.recognize(picture)
    let found = try #require(text.sensitive().first)
    #expect(found.kind == .email)
    #expect(found.text == "jane@example.com")
    let contact = try #require(text.lines.first?.words.first?.box)
    // The email's box starts after "Contact" and stays inside the line.
    #expect(found.box.minX > contact.maxX)
    #expect(found.box.minY >= 60 && found.box.maxY <= 130)
}

@Test func anImageWithNoTextHasNoLines() async throws {
    let text = try await TextRecognizer.recognize(try image(width: 200, height: 100, []))
    #expect(text.lines.isEmpty)
    #expect(text.string.isEmpty)
}

@Test func aFileThatIsntAnImageReadsAsNil() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("notes.txt")
    try Data("not an image".utf8).write(to: file)
    #expect(try await TextRecognizer.recognize(fileAt: file) == nil)
}
