// Renders Resources/AppIcon.icns and docs/icon.png (for the README). Run: make icon
import AppKit

let ink = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1)
let yellow = NSColor(srgbRed: 1, green: 0.83, blue: 0.23, alpha: 1)
let yellowLight = NSColor(srgbRed: 1, green: 0.89, blue: 0.40, alpha: 1)
let pink = NSColor(srgbRed: 1, green: 0.48, blue: 0.71, alpha: 1)

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824 pt body centered with 100 pt margin.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185
    let tile = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    yellow.setFill()
    tile.fill()
    ctx.restoreGState()
    NSGradient(starting: yellowLight, ending: yellow)!.draw(in: tile, angle: -90)

    // Viewfinder corner brackets.
    let inset: CGFloat = 195, arm: CGFloat = 150
    let frame = body.insetBy(dx: inset, dy: inset)
    let brackets = NSBezierPath()
    for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0), (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0), (CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0), (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0)] {
        brackets.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        brackets.line(to: corner)
        brackets.line(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
    }
    ink.setStroke()
    brackets.lineWidth = 56
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    brackets.stroke()

    // Shutter dot.
    let circle = NSBezierPath(ovalIn: CGRect(x: body.midX - 95, y: body.midY - 95, width: 190, height: 190))
    pink.setFill()
    circle.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try process.run()
process.waitUntilExit()
try render(size: 512).write(to: root.appendingPathComponent("docs/icon.png"))
print("Wrote Resources/AppIcon.icns and docs/icon.png")
