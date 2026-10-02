import CoreGraphics
import CoreText
import Testing
@testable import ShotCore

@Test func recognizesRenderedText() throws {
    let ctx = try #require(CGContext(data: nil, width: 600, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 120))
    let layout = TextLayout(string: "Hello Shot 123", fontSize: 32, color: RGBA(0, 0, 0))
    ctx.textPosition = CGPoint(x: 20, y: 45)
    CTLineDraw(try #require(layout.lines.first), ctx)
    let text = try OCR.recognizeText(in: try #require(ctx.makeImage()))
    #expect(text == "Hello Shot 123")
}
