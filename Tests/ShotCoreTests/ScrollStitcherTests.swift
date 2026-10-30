import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import ShotCore

// MARK: - A page to scroll

/// A made-up page, drawn with real text at whatever fractional offset the view is at, as a trackpad scrolls a real one,
/// so joins are tested against text that's rasterised a little differently in every frame. Parts of the view can stay
/// put: a header whose text scrolls sideways but not up and down, a footer, a first column that scrolls up and down but
/// not sideways, a floating button, and a patch that changes every frame like a video.
struct ScrollScene {
    var content = CGSize(width: 1400, height: 3000)
    var viewport = CGSize(width: 480, height: 320)
    var scale = 2
    var table = false
    var header: CGFloat = 0
    var footer: CGFloat = 0
    var column: CGFloat = 0
    var fab: CGRect?
    var video: CGRect?
    var blank = false

    static let fabColor = (r: 255, g: 0, b: 255)

    private static let words = ["ticket", "order", "refund", "mug", "shipped", "customer", "support", "balance", "card", "address", "delivery", "invoice", "note", "reply", "assign", "priority", "open", "closed", "pending", "escalated"]

    /// The view with its top left at `offset` points into the content; `index` seeds the video patch.
    func frame(at offset: CGPoint, index: Int = 0) -> Bitmap {
        let ctx = context(size: viewport)
        ctx.saveGState()
        ctx.translateBy(x: -offset.x, y: -offset.y)
        drawContent(ctx)
        ctx.restoreGState()
        if header > 0 {
            ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.95, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: viewport.width, height: header))
            ctx.setFillColor(CGColor(gray: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: header - 1, width: viewport.width, height: 1))
            drawBandText(ctx, along: .horizontal, origin: offset.x, extent: viewport.width, cross: header / 2 + 5, label: "Header")
        }
        if footer > 0 {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.96, blue: 0.9, alpha: 1))
            ctx.fill(CGRect(x: 0, y: viewport.height - footer, width: viewport.width, height: footer))
            drawBandText(ctx, along: .horizontal, origin: offset.x, extent: viewport.width, cross: viewport.height - footer / 2 + 5, label: "Footer")
        }
        if column > 0 {
            ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: column, height: viewport.height))
            ctx.setFillColor(CGColor(gray: 0.6, alpha: 1))
            ctx.fill(CGRect(x: column - 1, y: 0, width: 1, height: viewport.height))
            drawBandText(ctx, along: .vertical, origin: offset.y, extent: viewport.height, cross: 8, label: "Row")
            if header > 0 {
                ctx.setFillColor(CGColor(srgbRed: 0.85, green: 0.85, blue: 0.9, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: column, height: header))
                draw(ctx, "Sheet", at: CGPoint(x: 8, y: header / 2 + 5), bold: true)
            }
        }
        if let fab {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1))
            ctx.fillEllipse(in: fab)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: fab.midX - 8, y: fab.midY - 2, width: 16, height: 4))
            ctx.fill(CGRect(x: fab.midX - 2, y: fab.midY - 8, width: 4, height: 16))
        }
        if let video {
            var state = UInt64(index &+ 1) &* 0x9E37_79B9_7F4A_7C15
            let cell: CGFloat = 6
            var y = video.minY
            while y < video.maxY {
                var x = video.minX
                while x < video.maxX {
                    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    let grey = CGFloat((state >> 40) & 0xFF) / 255
                    ctx.setFillColor(CGColor(gray: grey, alpha: 1))
                    ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
                    x += cell
                }
                y += cell
            }
        }
        return ctx.makeBitmap()!
    }

    /// The content alone, `size` points from `origin`, as the stitched image should show it.
    func truth(from origin: CGPoint, size: CGSize) -> Bitmap {
        let ctx = context(size: size)
        ctx.translateBy(x: -origin.x, y: -origin.y)
        drawContent(ctx)
        return ctx.makeBitmap()!
    }

    /// The header as it should appear in the image: `width` points of it from content x `origin`.
    func headerStrip(from origin: CGFloat, width: CGFloat) -> Bitmap {
        let ctx = context(size: CGSize(width: width, height: header))
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.95, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: header))
        ctx.setFillColor(CGColor(gray: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: header - 1, width: width, height: 1))
        drawBandText(ctx, along: .horizontal, origin: origin, extent: width, cross: header / 2 + 5, label: "Header")
        return ctx.makeBitmap()!
    }

    private enum Axis { case horizontal, vertical }

    /// Labels every 100 points along a band that scrolls on one axis only.
    private func drawBandText(_ ctx: CGContext, along axis: Axis, origin: CGFloat, extent: CGFloat, cross: CGFloat, label: String) {
        var i = Int((origin / 100).rounded(.down))
        while CGFloat(i) * 100 < origin + extent {
            let along = CGFloat(i) * 100 - origin + 6
            if along > -60 {
                let text = "\(label) \(i)"
                switch axis {
                case .horizontal: draw(ctx, text, at: CGPoint(x: along, y: cross), bold: true)
                case .vertical: draw(ctx, text, at: CGPoint(x: cross, y: along + 14), bold: false)
                }
            }
            i += 1
        }
    }

    private func drawContent(_ ctx: CGContext) {
        guard !blank else {
            return
        }
        if table {
            let rowHeight: CGFloat = 24, columnWidth: CGFloat = 110
            ctx.setFillColor(CGColor(gray: 0.82, alpha: 1))
            var y: CGFloat = 0
            while y < content.height {
                ctx.fill(CGRect(x: 0, y: y, width: content.width, height: 1))
                y += rowHeight
            }
            var x: CGFloat = 0
            while x < content.width {
                ctx.fill(CGRect(x: x, y: 0, width: 1, height: content.height))
                x += columnWidth
            }
            var row = 0
            while CGFloat(row) * rowHeight < content.height {
                var col = 0
                while CGFloat(col) * columnWidth < content.width {
                    let value = (row * 7919 + col * 104_729) % 100_000
                    draw(ctx, String(format: "%d.%02d", value / 100, value % 100), at: CGPoint(x: CGFloat(col) * columnWidth + 10, y: CGFloat(row) * rowHeight + 16), bold: false)
                    col += 1
                }
                row += 1
            }
        } else {
            var y: CGFloat = 18
            var n = 0
            while y < content.height {
                var x: CGFloat = 12
                while x < content.width - 80 {
                    let word = Self.words[(n * 31 + Int(y)) % Self.words.count]
                    draw(ctx, n % 7 == 0 ? word.capitalized : word, at: CGPoint(x: x, y: y), bold: n % 11 == 0)
                    x += CGFloat(word.count) * 7.5 + 9
                    n += 1
                }
                y += 22
            }
        }
    }

    private func draw(_ ctx: CGContext, _ text: String, at position: CGPoint, bold: Bool) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, 13, nil)
        let attributed = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0.1, alpha: 1)])
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = position
        CTLineDraw(line, ctx)
    }

    /// A white, top-left-origin context in points at `scale`, rendering text at fractional positions.
    private func context(size: CGSize) -> CGContext {
        let width = Int((size.width * CGFloat(scale)).rounded()), height = Int((size.height * CGFloat(scale)).rounded())
        let ctx = CGContext.bitmap(width: width, height: height, format: .sRGB)!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setShouldSubpixelQuantizeFonts(false)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width + 1, height: size.height + 1))
        return ctx
    }
}

// MARK: - Helpers

/// Feeds the view at each offset to a stitcher and gives back the stitched image.
func stitch(_ scene: ScrollScene, offsets: [CGPoint], stitcher: ScrollStitcher? = nil) -> (stitcher: ScrollStitcher, image: Bitmap?, statuses: [ScrollCaptureStatus]) {
    let stitcher = stitcher ?? ScrollStitcher(width: Int(scene.viewport.width) * scene.scale, height: Int(scene.viewport.height) * scene.scale, scale: scene.scale, byteOrder: .rgba)
    var statuses: [ScrollCaptureStatus] = []
    for (index, offset) in offsets.enumerated() {
        let bitmap = scene.frame(at: offset, index: index)
        bitmap.pixels.withUnsafeBytes { bytes in
            let frame = ScrollFrame(width: bitmap.width, height: bitmap.height, bytesPerRow: bitmap.bytesPerRow, pixels: bytes)
            statuses.append(stitcher.process(frame).status)
        }
    }
    return (stitcher, stitcher.image().flatMap { Bitmap($0) }, statuses)
}

/// Offsets from `start` moving by each step in turn.
func path(from start: CGPoint = .zero, steps: [CGPoint]) -> [CGPoint] {
    var offsets = [start]
    for step in steps {
        offsets.append(CGPoint(x: offsets.last!.x + step.x, y: offsets.last!.y + step.y))
    }
    return offsets
}

func down(_ amounts: [CGFloat]) -> [CGPoint] { amounts.map { CGPoint(x: 0, y: $0) } }
func right(_ amounts: [CGFloat]) -> [CGPoint] { amounts.map { CGPoint(x: $0, y: 0) } }

/// How far `image` is from `truth` over the seen pixels outside `excluding` (pixel rects): the mean absolute
/// difference, the worst 32-pixel band's, which a duplicated or missing line of text shows up in, and the fraction
/// of pixels outside `excluding` that were never seen.
func difference(_ image: Bitmap, _ truth: Bitmap, excluding: [CGRect] = []) -> (mean: Double, worstBand: Double, worstBandAt: Int, unseen: Double, unseenBox: CGRect) {
    precondition(image.width == truth.width && image.height == truth.height, "\(image.width)×\(image.height) vs \(truth.width)×\(truth.height)")
    var total = 0.0, count = 0.0, unseen = 0.0, considered = 0.0
    var box = CGRect.null
    var worst = 0.0, worstAt = 0
    let band = 32
    var y = 0
    while y < image.height {
        var bandSum = 0.0, bandCount = 0.0
        for row in y..<min(y + band, image.height) {
            for x in 0..<image.width {
                if excluding.contains(where: { $0.contains(CGPoint(x: x, y: row)) }) {
                    continue
                }
                considered += 1
                let a = image[x, row], b = truth[x, row]
                if a.a == 0 {
                    unseen += 1
                    box = box.union(CGRect(x: x, y: row, width: 1, height: 1))
                    continue
                }
                bandSum += (abs(Double(a.r) - Double(b.r)) + abs(Double(a.g) - Double(b.g)) + abs(Double(a.b) - Double(b.b))) / 3
                bandCount += 1
            }
        }
        if bandCount > 0, bandSum / bandCount > worst {
            worst = bandSum / bandCount
            worstAt = y
        }
        total += bandSum
        count += bandCount
        y += band
    }
    return (count > 0 ? total / count : 0, worst, worstAt, considered > 0 ? unseen / considered : 0, box)
}

/// The fraction of the stitched image the views along `offsets` never showed content in, from the stitcher's own
/// geometry: what's under the sticky header, footer and column is never seen, and the bands themselves count as seen
/// along the edges they stick to.
func expectedUnseen(_ scene: ScrollScene, offsets: [CGPoint], stitcher: ScrollStitcher) -> Double {
    let seen = stitcher.canvas.seen!
    let scale = scene.scale
    let width = Int(scene.viewport.width) * scale, height = Int(scene.viewport.height) * scale
    let header = Int(scene.header) * scale, footer = Int(scene.footer) * scale, column = Int(scene.column) * scale
    var covered = [Bool](repeating: false, count: seen.width * seen.height)
    func cover(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        for y in max(0, y0)..<min(seen.height, y1) {
            for x in max(0, x0)..<min(seen.width, x1) {
                covered[y * seen.width + x] = true
            }
        }
    }
    let origins = offsets.map { (x: Int((($0.x - offsets[0].x) * CGFloat(scale)).rounded()) - seen.x0, y: Int((($0.y - offsets[0].y) * CGFloat(scale)).rounded()) - seen.y0) }
    let minX = origins.map(\.x).min()!, minY = origins.map(\.y).min()!, maxY = origins.map(\.y).max()!
    for origin in origins {
        cover(origin.x + column, origin.y + header, origin.x + width, origin.y + height - footer)
        // The header and footer stitch along x at the top and bottom edges; the column along y at the left.
        cover(origin.x, minY, origin.x + width, minY + header)
        cover(origin.x, maxY + height - footer, origin.x + width, maxY + height)
        cover(minX, origin.y, minX + column, origin.y + height)
    }
    return 1 - Double(covered.filter { $0 }.count) / Double(covered.count)
}

/// The content the stitched image should show, from the first view's offset and the stitcher's own geometry.
func expectedTruth(_ scene: ScrollScene, start: CGPoint, stitcher: ScrollStitcher) -> Bitmap {
    let seen = stitcher.canvas.seen!
    let scale = CGFloat(scene.scale)
    return scene.truth(from: CGPoint(x: start.x + CGFloat(seen.x0) / scale, y: start.y + CGFloat(seen.y0) / scale), size: CGSize(width: CGFloat(seen.width) / scale, height: CGFloat(seen.height) / scale))
}

/// How many pixels of `image` are the floating button's magenta.
func fabPixels(in image: Bitmap) -> Int {
    var n = 0
    for y in 0..<image.height {
        for x in 0..<image.width {
            let p = image[x, y]
            if p.r > 200, p.g < 60, p.b > 200 {
                n += 1
            }
        }
    }
    return n
}

// MARK: - Lining up

@Test func phaseCorrelationFindsTheMoveAndItsWrapAround() {
    let scene = ScrollScene(viewport: CGSize(width: 128, height: 96), scale: 1)
    func grey(_ bitmap: Bitmap) -> [Float] {
        (0..<bitmap.height).flatMap { y in (0..<bitmap.width).map { x in let p = bitmap[x, y]; return (Float(p.r) + Float(p.g) + Float(p.b)) / 3 } }
    }
    let correlator = PhaseCorrelator(width: 128, height: 96)
    let peaks = correlator.peaks(from: grey(scene.frame(at: CGPoint(x: 100, y: 200))), to: grey(scene.frame(at: CGPoint(x: 107, y: 229))), count: 3)
    #expect(peaks.contains { $0.dx == 7 && $0.dy == 29 })
    #expect(peaks.first.map { ($0.dx, $0.dy) == (7, 29) || ($0.dx, $0.dy) == (7 - 128, 29 - 128) || ($0.dx, $0.dy) == (7, 29 - 128) || ($0.dx, $0.dy) == (7 - 128, 29) } == true)
}

@Test func aLongPageScrolledAtASteadyThenAVariablePaceIsOneImage() throws {
    let scene = ScrollScene()
    let offsets = path(steps: down([20, 20, 20, 20, 20, 20, 37, 5, 90, 12, 61, 3.5, 44.25, 70, 18]))
    let (stitcher, image, statuses) = stitch(scene, offsets: offsets)
    let result = try #require(image)
    #expect(statuses.dropFirst().allSatisfy { $0 == .live }, "\(statuses)")
    let total = offsets.last!.y
    #expect(abs(CGFloat(result.height) - (scene.viewport.height + total) * 2) <= 2)
    #expect(result.width == Int(scene.viewport.width) * 2)
    let truth = expectedTruth(scene, start: .zero, stitcher: stitcher)
    let d = difference(result, truth)
    #expect(d.mean < 6, "mean \(d.mean)")
    #expect(d.worstBand < 20, "worst band \(d.worstBand) at \(d.worstBandAt)")
}

@Test func aWideTableScrolledSidewaysIsOneImage() throws {
    let scene = ScrollScene(table: true)
    let offsets = path(steps: right([30, 30, 55, 12, 80, 33.3, 47, 60, 25]))
    let (stitcher, image, statuses) = stitch(scene, offsets: offsets)
    let result = try #require(image)
    #expect(statuses.dropFirst().allSatisfy { $0 == .live }, "\(statuses)")
    #expect(abs(CGFloat(result.width) - (scene.viewport.width + offsets.last!.x) * 2) <= 2)
    let d = difference(result, expectedTruth(scene, start: .zero, stitcher: stitcher))
    #expect(d.mean < 6, "mean \(d.mean)")
    #expect(d.worstBand < 20, "worst band \(d.worstBand) at \(d.worstBandAt)")
    #expect(d.unseen == 0, "unseen \(d.unseen) in \(d.unseenBox)")
}

@Test func aSpreadsheetKeepsItsHeaderRowOnceAtTheTopAndItsFirstColumnOnceAtTheLeft() throws {
    let scene = ScrollScene(table: true, header: 28, column: 90)
    let offsets = path(steps: down([24, 36, 48, 30, 20]) + right([40, 55, 60, 35]) + [CGPoint(x: 30, y: 40), CGPoint(x: 45, y: 25), CGPoint(x: 20, y: 50)])
    let (stitcher, image, statuses) = stitch(scene, offsets: offsets)
    let result = try #require(image)
    #expect(statuses.dropFirst().allSatisfy { $0 == .live }, "\(statuses)")
    let last = offsets.last!
    #expect(abs(CGFloat(result.width) - (scene.viewport.width + last.x) * 2) <= 2)
    #expect(abs(CGFloat(result.height) - (scene.viewport.height + last.y) * 2) <= 2)
    let headerBand = CGRect(x: 0, y: 0, width: CGFloat(result.width), height: scene.header * 2)
    let columnBand = CGRect(x: 0, y: 0, width: scene.column * 2, height: CGFloat(result.height))
    let d = difference(result, expectedTruth(scene, start: .zero, stitcher: stitcher), excluding: [headerBand, columnBand])
    #expect(d.mean < 6, "mean \(d.mean)")
    #expect(d.worstBand < 20, "worst band \(d.worstBand) at \(d.worstBandAt)")
    // The corners the view never reached stay clear, and nothing else does.
    let unseen = difference(result, expectedTruth(scene, start: .zero, stitcher: stitcher)).unseen
    let expected = expectedUnseen(scene, offsets: offsets, stitcher: stitcher)
    #expect(abs(unseen - expected) < 0.01, "unseen \(unseen) expected \(expected)")
    // The header strip runs the width of the image, with its text where the content's x says.
    let strip = scene.headerStrip(from: 0, width: CGFloat(result.width) / 2)
    var stripDiff = 0.0
    for y in 0..<strip.height {
        for x in 0..<(strip.width - Int(scene.column) * 2) {
            let a = result[x + Int(scene.column) * 2, y], b = strip[x + Int(scene.column) * 2, y]
            stripDiff += (abs(Double(a.r) - Double(b.r)) + abs(Double(a.g) - Double(b.g)) + abs(Double(a.b) - Double(b.b))) / 3
        }
    }
    #expect(stripDiff / Double(strip.width * strip.height) < 8)
}

@Test func aFlickThatDecaysAndADroppedFrameStillLineUp() throws {
    let scene = ScrollScene()
    let offsets = path(steps: down([180, 150, 110, 70, 40, 20, 8, 3, 1, 0.5, 0.25, 200, 160]))
    let (stitcher, image, statuses) = stitch(scene, offsets: offsets)
    let result = try #require(image)
    #expect(statuses.dropFirst().allSatisfy { $0 == .live }, "\(statuses)")
    #expect(abs(CGFloat(result.height) - (scene.viewport.height + offsets.last!.y) * 2) <= 2)
    let d = difference(result, expectedTruth(scene, start: .zero, stitcher: stitcher))
    #expect(d.mean < 6, "mean \(d.mean)")
    #expect(d.worstBand < 20, "worst band \(d.worstBand) at \(d.worstBandAt)")
    #expect(d.unseen == 0, "unseen \(d.unseen) in \(d.unseenBox)")
}

@Test func scrollingBackOverCapturedContentLeavesTheImageAlone() throws {
    let scene = ScrollScene()
    let there = path(steps: down([40, 40, 40, 40, 40, 40]))
    let (stitcher, first, _) = stitch(scene, offsets: there)
    let before = try #require(first)
    let back = path(from: there.last!, steps: down([-30, -50, -70, -20, 45, 60, 65]))
    let (_, second, statuses) = stitch(scene, offsets: Array(back.dropFirst()), stitcher: stitcher)
    let after = try #require(second)
    #expect(statuses.allSatisfy { $0 == .live }, "\(statuses)")
    #expect(after.width == before.width && after.height == before.height)
    let d = difference(after, before)
    #expect(d.mean < 2, "mean \(d.mean)")
    #expect(d.worstBand < 8, "worst band \(d.worstBand) at \(d.worstBandAt)")
}

@Test func startingInTheMiddleAndScrollingUpExtendsTheImageUpwards() throws {
    let scene = ScrollScene()
    let start = CGPoint(x: 0, y: 1000)
    let offsets = path(from: start, steps: down([-30, -45, -60, -25, -40.5]))
    let (stitcher, image, statuses) = stitch(scene, offsets: offsets)
    let result = try #require(image)
    #expect(statuses.dropFirst().allSatisfy { $0 == .live }, "\(statuses)")
    #expect(abs(CGFloat(result.height) - (scene.viewport.height + 200.5) * 2) <= 2)
    let d = difference(result, expectedTruth(scene, start: start, stitcher: stitcher))
    #expect(d.mean < 6, "mean \(d.mean)")
    #expect(d.worstBand < 20, "worst band \(d.worstBand) at \(d.worstBandAt)")
    #expect(d.unseen == 0, "unseen \(d.unseen) in \(d.unseenBox)")
}

@Test func aJumpTooBigToFollowWarnsAndScrollingBackRecovers() throws {
    let scene = ScrollScene()
    let offsets = path(steps: down([30, 30, 300, -150, 40]))
    let (stitcher, image, statuses) = stitch(scene, offsets: offsets)
    let result = try #require(image)
    #expect(statuses == [.ready, .live, .live, .tooFar, .live, .live], "\(statuses)")
    // The far frame was never painted; the image ends where the last lined-up frame does.
    #expect(abs(CGFloat(result.height) - (scene.viewport.height + 60 + 150 + 40) * 2) <= 2)
    let d = difference(result, expectedTruth(scene, start: .zero, stitcher: stitcher))
    #expect(d.mean < 6, "mean \(d.mean)")
    #expect(d.worstBand < 20, "worst band \(d.worstBand) at \(d.worstBandAt)")
    #expect(d.unseen == 0, "unseen \(d.unseen) in \(d.unseenBox)")
}

@Test func aVideoThatFillsTheAreaWarnsThatSomethingKeepsChanging() {
    let scene = ScrollScene(video: CGRect(x: 10, y: 10, width: 460, height: 300))
    let (_, _, statuses) = stitch(scene, offsets: path(steps: down([0, 0, 0, 20, 20])))
    #expect(statuses.last == .changing, "\(statuses)")
}

@Test func aSmallVideoInTheAreaDoesNotStopTheCapture() throws {
    let scene = ScrollScene(video: CGRect(x: 300, y: 100, width: 120, height: 80))
    let offsets = path(steps: down([25, 30, 35, 20, 40]))
    let (stitcher, image, statuses) = stitch(scene, offsets: offsets)
    let result = try #require(image)
    #expect(statuses.dropFirst().allSatisfy { $0 == .live }, "\(statuses)")
    let videoAtEnd = CGRect(x: 600, y: CGFloat(result.height) - 640 + 200, width: 240, height: 160)
    let d = difference(result, expectedTruth(scene, start: .zero, stitcher: stitcher), excluding: [videoAtEnd])
    #expect(d.mean < 8, "mean \(d.mean)")
}

@Test func aBlankAreaSaysThereIsNotEnoughToLineUp() {
    let scene = ScrollScene(blank: true)
    let (stitcher, _, statuses) = stitch(scene, offsets: path(steps: down([20, 20])))
    #expect(statuses.last == .notEnough, "\(statuses)")
    #expect(stitcher.size == CGSize(width: 960, height: 640))
}

@Test func aStickyHeaderFooterAndFloatingButtonAppearOnce() throws {
    let fab = CGRect(x: 420, y: 250, width: 44, height: 44)
    let scene = ScrollScene(header: 36, footer: 30, fab: fab)
    let offsets = path(steps: down([20, 30, 45, 25, 60, 35, 50, 40, 15, 70]))
    let (stitcher, image, statuses) = stitch(scene, offsets: offsets)
    let result = try #require(image)
    #expect(statuses.dropFirst().allSatisfy { $0 == .live }, "\(statuses)")
    let height = CGFloat(result.height)
    let headerBand = CGRect(x: 0, y: 0, width: CGFloat(result.width), height: scene.header * 2)
    let footerBand = CGRect(x: 0, y: height - scene.footer * 2, width: CGFloat(result.width), height: scene.footer * 2)
    let fabAtEnd = CGRect(x: fab.minX * 2, y: height - (scene.viewport.height - fab.minY) * 2, width: fab.width * 2, height: fab.height * 2)
    let d = difference(result, expectedTruth(scene, start: .zero, stitcher: stitcher), excluding: [headerBand, footerBand, fabAtEnd])
    #expect(d.mean < 6, "mean \(d.mean)")
    #expect(d.worstBand < 20, "worst band \(d.worstBand) at \(d.worstBandAt)")
    #expect(d.unseen == 0, "unseen \(d.unseen) in \(d.unseenBox)")
    // The button is at the bottom right, once: its pixels add up to about one disc.
    let disc = Double.pi * Double(fab.width * fab.height) / 4 * 4
    let magenta = Double(fabPixels(in: result))
    #expect(magenta > disc * 0.5 && magenta < disc * 1.3, "\(magenta) of \(disc)")
}

@Test func tinyFractionalScrollsNeverSmearAStickyHeader() throws {
    let scene = ScrollScene(header: 36)
    let offsets = path(steps: down(Array(repeating: 0.5, count: 12) + Array(repeating: 1.25, count: 10) + [4, 4, 6]))
    let (stitcher, image, statuses) = stitch(scene, offsets: offsets)
    let result = try #require(image)
    #expect(statuses.dropFirst().allSatisfy { $0 == .live }, "\(statuses)")
    let headerBand = CGRect(x: 0, y: 0, width: CGFloat(result.width), height: scene.header * 2 + 4)
    let d = difference(result, expectedTruth(scene, start: .zero, stitcher: stitcher), excluding: [headerBand])
    #expect(d.mean < 6, "mean \(d.mean)")
    #expect(d.worstBand < 20, "worst band \(d.worstBand) at \(d.worstBandAt)")
    #expect(d.unseen == 0, "unseen \(d.unseen) in \(d.unseenBox)")
}

@Test func theSizeLimitStopsGrowthAndKeepsWhatWasCaptured() throws {
    let limits = ScrollCaptureLimits(maxSide: 1200, maxPixels: 2_000_000)
    let scene = ScrollScene(viewport: CGSize(width: 240, height: 160), scale: 2)
    let stitcher = ScrollStitcher(width: 480, height: 320, scale: 2, byteOrder: .rgba, limits: limits)
    let (_, image, statuses) = stitch(scene, offsets: path(steps: down(Array(repeating: 60, count: 10))), stitcher: stitcher)
    let result = try #require(image)
    #expect(statuses.last == .sizeLimit, "\(statuses)")
    #expect(result.height <= 1200)
    #expect(result.height > 1000)
    #expect(stitcher.size.height <= 1200)
}

// MARK: - The canvas

@Test func theCanvasTrimsOnlyWhatItAdds() {
    // Both sides grew, so both give some up, in whole cells.
    let both = ScrollCanvas.clamp(old: (0, 800), wanted: (-400, 1200), to: 1000)
    #expect(both.1 - both.0 == 1000 && both.0 <= 0 && both.1 >= 800 && both.0 % 8 == 0 && both.1 % 8 == 0, "\(both)")
    #expect(ScrollCanvas.clamp(old: (0, 800), wanted: (0, 1600), to: 1000) == (0, 1000))
    #expect(ScrollCanvas.clamp(old: (0, 800), wanted: (-800, 800), to: 1000) == (-200, 800))
    // What the canvas already holds is never trimmed.
    #expect(ScrollCanvas.clamp(old: (0, 800), wanted: (0, 800), to: 400) == (0, 800))
}

// MARK: - The panel

@Test func everyStatusHasAChipAndWarningsHaveAMessage() {
    for status in [ScrollCaptureStatus.ready, .live, .tooFar, .changing, .notEnough, .sizeLimit] {
        #expect(!status.title.isEmpty)
    }
    #expect(ScrollCaptureStatus.live.message == nil)
    #expect(ScrollCaptureStatus.ready.message == "Scroll the content in any direction.")
    #expect(ScrollCaptureStatus.tooFar.message == "Scrolled too far at once. Scroll back a little and carry on.")
    #expect(ScrollCaptureStatus.changing.message == "Something in the area keeps changing, so Shot can't line frames up. Pause the video or scroll past it.")
    #expect(ScrollCaptureStatus.notEnough.message == "There isn't enough in the area to line frames up. Include some text or an image, or drag out another area.")
    #expect(ScrollCaptureStatus.sizeLimit.message == "The image is as big as Shot can stitch. Press Return to save it.")
    #expect([ScrollCaptureStatus.tooFar, .changing, .notEnough].allSatisfy { $0.isWarning })
    #expect(![ScrollCaptureStatus.ready, .live, .sizeLimit].contains { $0.isWarning })
}

@Test func thePanelGoesBesideTheAreaAndNeverOverIt() {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let size = CGSize(width: 260, height: 300)
    // Right of the area, top-aligned.
    #expect(ScrollCapturePanelPlacement.origin(for: size, region: CGRect(x: 100, y: 200, width: 600, height: 400), visible: visible) == CGPoint(x: 714, y: 300))
    // Left when the right is full.
    #expect(ScrollCapturePanelPlacement.origin(for: size, region: CGRect(x: 600, y: 200, width: 800, height: 400), visible: visible) == CGPoint(x: 326, y: 300))
    // Below when both sides are full.
    #expect(ScrollCapturePanelPlacement.origin(for: size, region: CGRect(x: 50, y: 400, width: 1340, height: 400), visible: visible) == CGPoint(x: 50, y: 86))
    // Above when there's no room below.
    #expect(ScrollCapturePanelPlacement.origin(for: size, region: CGRect(x: 50, y: 0, width: 1340, height: 400), visible: visible) == CGPoint(x: 50, y: 414))
    // A full-screen area leaves only the inside; the panel sits in its bottom-right corner.
    let inside = ScrollCapturePanelPlacement.origin(for: size, region: visible, visible: visible)
    #expect(inside == CGPoint(x: 1166, y: 14))
    // Kept on screen when the area's top is above the visible frame's.
    let clamped = ScrollCapturePanelPlacement.origin(for: size, region: CGRect(x: 100, y: 700, width: 300, height: 300), visible: visible)
    #expect(clamped == CGPoint(x: 414, y: 567))
}

@Test func captureScrollingHasAShortcutButNoDefault() throws {
    #expect(ShotAction.captureScrolling.rawValue == "capture-scrolling")
    #expect(!ShotAction.captureScrolling.isRecording)
    #expect(ShotAction.captureScrolling.hasShortcut)
    #expect(ShotAction.captureScrolling.defaultCombo == nil)
    #expect(ShotAction.captureScrolling.defaultCombo(replacingSystemScreenshots: true) == nil)
    #expect(ShotAction.allCases.last == .captureScrolling)
    #expect(ShotAction.captureScrolling.title == "Capture Scrolling Area")
    let url = try #require(URL(string: "shot://capture-scrolling"))
    let route = try ShotURL(url)
    #expect(route == .action(.captureScrolling))
}

@Test func stickyPartsArePaintedAsStickyAndTheRestAsContent() throws {
    let scene = ScrollScene(header: 36, footer: 30)
    let (stitcher, _, _) = stitch(scene, offsets: path(steps: down([20, 30, 45, 25, 60])))
    let owners = try #require(stitcher.canvas.ownerImage().flatMap { Bitmap($0) })
    // The header strip and the footer strip are sticky paint; the text between them is content.
    #expect(owners[480, 20].r > 200 && owners[480, 20].g < 100, "header")
    #expect(owners[480, owners.height - 20].r > 200 && owners[480, owners.height - 20].g > 150, "footer")
    #expect(owners[480, owners.height / 2] == (255, 255, 255, 255), "content")
}
