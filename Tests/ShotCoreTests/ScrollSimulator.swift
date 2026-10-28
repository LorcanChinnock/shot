import CoreGraphics
import CoreText
import Foundation

@testable import ShotCore

/// A spreadsheet-like page drawn with real text at any, including fractional, scroll offset, as an app draws it while
/// scrolling: shapes land between pixels, so no two frames of the same content are quite the same.
///
/// `header`, `footer` and `leftColumn` are sizes in pixels of parts that stay on screen. The header scrolls sideways with
/// the content, and the left column up and down, as a spreadsheet's do.
struct ScrollSimulator: Sendable {
    var width = 360
    var height = 300
    var cellWidth = 118.0
    var cellHeight = 34.0
    var header = 0
    var footer = 0
    var leftColumn = 0
    /// A box that stays put on screen over the content, such as a floating button.
    var floating: CGRect?

    private var font: CTFont { CTFontCreateWithName("Helvetica" as CFString, 15, nil) }

    func text(row: Int, column: Int) -> String {
        "\((row * 7919 + column * 104_729) % 9973) · r\(row)c\(column)"
    }

    /// The area with the page scrolled to (`x`, `y`) pixels.
    func frame(x: Double, y: Double) -> Bitmap {
        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            // Top-left origin.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            drawCells(context, x: x, y: y)
            if header > 0 { drawHeader(context, x: x) }
            if leftColumn > 0 { drawLeftColumn(context, y: y) }
            if footer > 0 { drawFooter(context) }
            if let floating {
                context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.9, alpha: 1))
                context.fill(floating)
                draw("Help", at: CGPoint(x: floating.minX + 6, y: floating.minY + 20), in: context, white: true)
            }
        }
        return Bitmap(width: width, height: height, pixels: pixels.withUnsafeBytes { Data($0) })!
    }

    private func drawCells(_ context: CGContext, x: Double, y: Double) {
        let firstRow = max(0, Int(floor(y / cellHeight))), lastRow = Int(ceil((y + Double(height)) / cellHeight))
        let firstColumn = max(0, Int(floor(x / cellWidth))), lastColumn = Int(ceil((x + Double(width)) / cellWidth))
        context.setStrokeColor(CGColor(gray: 0.8, alpha: 1))
        context.setLineWidth(1)
        for row in firstRow...lastRow {
            let top = Double(row) * cellHeight - y
            context.move(to: CGPoint(x: 0, y: top))
            context.addLine(to: CGPoint(x: Double(width), y: top))
            for column in firstColumn...lastColumn {
                draw(text(row: row, column: column), at: CGPoint(x: Double(column) * cellWidth - x + 8, y: top + 22), in: context)
            }
        }
        for column in firstColumn...lastColumn {
            let left = Double(column) * cellWidth - x
            context.move(to: CGPoint(x: left, y: 0))
            context.addLine(to: CGPoint(x: left, y: Double(height)))
        }
        context.strokePath()
    }

    private func drawHeader(_ context: CGContext, x: Double) {
        context.setFillColor(CGColor(red: 1, green: 0.83, blue: 0.23, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: header))
        for column in max(0, Int(floor(x / cellWidth)))...Int(ceil((x + Double(width)) / cellWidth)) {
            draw("Col \(column)", at: CGPoint(x: Double(column) * cellWidth - x + 8, y: Double(header) * 0.7), in: context)
        }
    }

    private func drawLeftColumn(_ context: CGContext, y: Double) {
        context.setFillColor(CGColor(red: 0.92, green: 0.96, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: Double(header), width: Double(leftColumn), height: Double(height - header)))
        for row in max(0, Int(floor(y / cellHeight)))...Int(ceil((y + Double(height)) / cellHeight)) {
            draw("R\(row)", at: CGPoint(x: 8, y: Double(row) * cellHeight - y + 22), in: context)
        }
        context.setFillColor(CGColor(red: 1, green: 0.72, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Double(leftColumn), height: Double(header)))
        if header > 0 { draw("#", at: CGPoint(x: 8, y: Double(header) * 0.7), in: context) }
    }

    private func drawFooter(_ context: CGContext) {
        context.setFillColor(CGColor(red: 0.43, green: 0.76, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: Double(height - footer), width: Double(width), height: Double(footer)))
        draw("Footer bar", at: CGPoint(x: 10, y: Double(height) - Double(footer) * 0.3), in: context)
    }

    private func draw(_ string: String, at point: CGPoint, in context: CGContext, white: Bool = false) {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: white ? 1 : 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary))
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = point
        CTLineDraw(line, context)
    }
}

/// Fraction of the image's painted pixels that are about the same as a rendering of the page at the same place, allowing
/// for text drawn at a fraction of a pixel, which lands a pixel away from where a whole-pixel rendering puts it.
func agreement(of result: Bitmap, with simulator: ScrollSimulator, origin: (x: Double, y: Double) = (0, 0)) -> Double {
    var big = simulator
    big.width = result.width
    big.height = result.height
    let truth = big.frame(x: origin.x, y: origin.y)
    var same = 0, total = 0
    for y in stride(from: 2, to: result.height - 2, by: 2) {
        for x in stride(from: 2, to: result.width - 2, by: 2) {
            let a = result[x, y]
            guard a.a != 0 else { continue }
            total += 1
            var best = Int.max
            for (dx, dy) in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)] {
                let b = truth[x + dx, y + dy]
                best = min(best, abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b)))
            }
            if best <= 120 { same += 1 }
        }
    }
    return total == 0 ? 0 : Double(same) / Double(total)
}
