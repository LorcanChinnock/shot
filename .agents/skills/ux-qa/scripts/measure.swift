import CoreGraphics
import Foundation
import ImageIO

// Measures custom-drawn UI that the accessibility tree can't see (timelines, canvases, lanes) from a screenshot.
//   measure FILE.png X Y W H [bg=#RRGGBB|auto] [tolerance=24]
//   measure FILE.png sample X Y
// FILE is a `uxqa_shot` image (1 px = 1 pt). The rect is the area to scan. Anything that differs from the background
// (the pixel at the rect's top-left, or the colour given) counts as content. Prints the content's bounding box and its
// vertical and horizontal runs, so centres and edges can be compared numerically instead of by eye:
//   measure win.png 400 1040 80 80          -> where the play button sits
//   measure win.png 480 1040 1100 160       -> the rows of the timeline: ruler text, lane strips, gaps

let args = CommandLine.arguments
// `measure FILE.png sample X Y` prints one pixel's colour as hex, for contrast checks.
if args.count == 5, args[2] == "sample", let px = Int(args[3]), let py = Int(args[4]),
   let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil), px < image.width, py < image.height {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -px, y: -(image.height - 1 - py), width: image.width, height: image.height))
    print(String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2]))
    exit(0)
}
guard args.count >= 6, let x = Int(args[2]), let y = Int(args[3]), let w = Int(args[4]), let h = Int(args[5]),
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("usage: measure FILE.png X Y W H [bg=auto|#RRGGBB] [tolerance=24]\n".utf8))
    exit(2)
}
let tolerance = args.count > 7 ? Int(args[7]) ?? 24 : 24

var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
func rgb(_ px: Int, _ py: Int) -> (Int, Int, Int) {
    let i = (py * image.width + px) * 4
    return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
}

let x1 = min(image.width, x + w), y1 = min(image.height, y + h)
var background = rgb(min(x, image.width - 1), min(y, image.height - 1))
if args.count > 6, args[6].hasPrefix("#"), let value = Int(args[6].dropFirst(), radix: 16) {
    background = (value >> 16 & 255, value >> 8 & 255, value & 255)
}
func isContent(_ px: Int, _ py: Int) -> Bool {
    let c = rgb(px, py)
    return abs(c.0 - background.0) + abs(c.1 - background.1) + abs(c.2 - background.2) > tolerance
}

var rows = [Bool](repeating: false, count: max(0, y1 - y)), columns = [Bool](repeating: false, count: max(0, x1 - x))
for py in y..<y1 {
    for px in x..<x1 where isContent(px, py) {
        rows[py - y] = true
        columns[px - x] = true
    }
}
func runs(_ flags: [Bool], offset: Int) -> [(Int, Int)] {
    var result: [(Int, Int)] = [], start: Int?
    for (index, on) in flags.enumerated() + [(flags.count, false)] {
        if on, start == nil { start = index }
        if !on, let begin = start { result.append((begin + offset, index - 1 + offset)); start = nil }
    }
    return result
}
let verticalRuns = runs(rows, offset: y), horizontalRuns = runs(columns, offset: x)
guard let top = verticalRuns.first?.0, let bottom = verticalRuns.last?.1, let left = horizontalRuns.first?.0, let right = horizontalRuns.last?.1 else {
    print("no content in the rect")
    exit(1)
}
print("background \(background)  bbox x \(left)…\(right) y \(top)…\(bottom)  size \(right - left + 1)×\(bottom - top + 1)  centre (\(Double(left + right) / 2), \(Double(top + bottom) / 2))")
print("rows   (y0…y1 height centre): " + verticalRuns.map { "\($0.0)…\($0.1) \($0.1 - $0.0 + 1) \(Double($0.0 + $0.1) / 2)" }.joined(separator: " | "))
print("columns(x0…x1 width centre):  " + horizontalRuns.prefix(24).map { "\($0.0)…\($0.1) \($0.1 - $0.0 + 1) \(Double($0.0 + $0.1) / 2)" }.joined(separator: " | "))
