// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let ink = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1)
let yellow = NSColor(srgbRed: 1, green: 0.83, blue: 0.23, alpha: 1)
let pink = NSColor(srgbRed: 1, green: 0.48, blue: 0.71, alpha: 1)

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824 pt body inset 100 pt.
    let body = CGRect(x: 100, y: 112, width: 800, height: 800)
    let radius: CGFloat = 180
    let shadow = NSBezierPath(roundedRect: body.offsetBy(dx: 22, dy: -22), xRadius: radius, yRadius: radius)
    ink.setFill()
    shadow.fill()
    let tile = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    yellow.setFill()
    tile.fill()
    tile.lineWidth = 30
    ink.setStroke()
    tile.stroke()

    // Viewfinder corner brackets.
    let inset: CGFloat = 175, arm: CGFloat = 150
    let frame = body.insetBy(dx: inset, dy: inset)
    let brackets = NSBezierPath()
    for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0), (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0), (CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0), (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0)] {
        brackets.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        brackets.line(to: corner)
        brackets.line(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
    }
    brackets.lineWidth = 56
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    brackets.stroke()

    // Shutter dot with its own hard shadow.
    let dot = CGRect(x: body.midX - 95, y: body.midY - 95, width: 190, height: 190)
    ink.setFill()
    NSBezierPath(ovalIn: dot.offsetBy(dx: 14, dy: -14)).fill()
    let circle = NSBezierPath(ovalIn: dot)
    pink.setFill()
    circle.fill()
    circle.lineWidth = 24
    circle.stroke()

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
try render(size: 512).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-preview.png"))
print("Wrote Resources/AppIcon.icns")
