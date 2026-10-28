import Foundation
import Testing

@testable import ShotCore

// The "page" is an endless sheet of noise, so every patch of it is different. A frame is the window of it the area shows
// at an offset, optionally with things painted on top that stay put on screen.

private let size = 80

private func noise(_ x: Int, _ y: Int, seed: UInt32 = 0) -> UInt32 {
    var h = UInt32(truncatingIfNeeded: x &* 73_856_093) ^ UInt32(truncatingIfNeeded: y &* 19_349_663) ^ (seed &* 83_492_791)
    h = (h ^ (h >> 13)) &* 0x5bd1_e995
    h ^= h >> 15
    return 0xff00_0000 | (h & 0x00ff_ffff)
}

private func page(_ x: Int, _ y: Int) -> UInt32 { noise(x, y) }

private func bitmap(width: Int, height: Int, _ pixel: (Int, Int) -> UInt32) -> Bitmap {
    var pixels = [UInt32]()
    pixels.reserveCapacity(width * height)
    for y in 0..<height {
        for x in 0..<width {
            pixels.append(pixel(x, y))
        }
    }
    return Bitmap(width: width, height: height, pixels: pixels.withUnsafeBytes { Data($0) })!
}

/// What the area shows with the page scrolled to (`ox`, `oy`); `overlay` returns the pixel painted over (x, y) of the
/// screen, if any.
private func frame(_ ox: Int, _ oy: Int, overlay: (Int, Int) -> UInt32? = { _, _ in nil }) -> Bitmap {
    bitmap(width: size, height: size) { x, y in overlay(x, y) ?? page(x + ox, y + oy) }
}

private func add(_ stitcher: inout ScrollStitcher, _ offsets: [(Int, Int)], overlay: (Int, Int) -> UInt32? = { _, _ in nil }) -> [ScrollStitcher.Outcome] {
    offsets.map { stitcher.add(frame($0.0, $0.1, overlay: overlay)) }
}

@Test func scrollStitcherJoinsFramesScrolledDown() {
    var stitcher = ScrollStitcher(first: frame(0, 0))
    #expect(add(&stitcher, [(0, 20), (0, 40)]) == [.extended, .extended])
    #expect(stitcher.size.width == size && stitcher.size.height == size + 40)
    #expect(stitcher.result == bitmap(width: size, height: size + 40, page))
}

@Test func scrollStitcherJoinsFramesScrolledSideways() {
    var stitcher = ScrollStitcher(first: frame(0, 0))
    _ = add(&stitcher, [(20, 0), (40, 0)])
    #expect(stitcher.result == bitmap(width: size + 40, height: size, page))
}

@Test func scrollStitcherFollowsScrollingAtAnAngle() {
    // Down and right at once, then back along two other sides, so the corners come into view.
    var stitcher = ScrollStitcher(first: frame(0, 0))
    _ = add(&stitcher, [(15, 15), (30, 30), (30, 15), (30, 0), (15, 15), (0, 30)])
    #expect(stitcher.size.width == size + 30 && stitcher.size.height == size + 30)
    #expect(stitcher.result == bitmap(width: size + 30, height: size + 30, page))
}

@Test func scrollStitcherJoinsOneCaptureScrolledAroundASquare() {
    var stitcher = ScrollStitcher(first: frame(0, 0))
    _ = add(&stitcher, [(0, 20), (0, 40), (20, 40), (40, 40), (40, 20), (40, 0), (20, 0), (0, 0)])
    #expect(stitcher.result == bitmap(width: size + 40, height: size + 40, page))
}

@Test func scrollStitcherAddsNothingWhenScrollingBack() {
    var stitcher = ScrollStitcher(first: frame(0, 0))
    #expect(add(&stitcher, [(0, 20), (0, 40)]) == [.extended, .extended])
    #expect(add(&stitcher, [(0, 20), (0, 0), (0, 0)]) == [.unchanged, .unchanged, .unchanged])
    #expect(stitcher.size.height == size + 40)
}

@Test func scrollStitcherGrowsUpwardAndLeftwardToo() {
    // Starts in the middle and scrolls up and left, which the image grows to include.
    var stitcher = ScrollStitcher(first: frame(40, 40))
    _ = add(&stitcher, [(20, 40), (0, 40), (0, 20), (0, 0)])
    #expect(stitcher.size.width == size + 40 && stitcher.size.height == size + 40)
    #expect(stitcher.result.pixels.count == (size + 40) * (size + 40) * 4)
    let result = stitcher.result
    // The frames cover an L, so check pixels of it against the page.
    #expect(result[5, 5].r == UInt8(page(5, 5) & 0xff))
    #expect(result[5, size + 30].r == UInt8(page(5, size + 30) & 0xff))
}

@Test func scrollStitcherKeepsAStickyHeaderAndFooterOnce() {
    func header(_ x: Int, _ y: Int) -> UInt32 { noise(x, y, seed: 7) }
    func footer(_ x: Int, _ y: Int) -> UInt32 { noise(x, y, seed: 9) }
    func overlay(_ x: Int, _ y: Int) -> UInt32? { y < 10 ? header(x, y) : (y >= size - 8 ? footer(x, y) : nil) }
    var stitcher = ScrollStitcher(first: frame(0, 0, overlay: overlay))
    _ = add(&stitcher, [(0, 20), (0, 40)], overlay: overlay)
    #expect(stitcher.size.height == size + 40)
    // The header is on screen at the top, the footer at the bottom of the last frame, and the page in between.
    let expected = bitmap(width: size, height: size + 40) { x, y in
        y < 10 ? header(x, y) : (y >= size + 40 - 8 ? footer(x, y - 40) : page(x, y))
    }
    #expect(stitcher.result == expected)
}

@Test func scrollStitcherLeavesOutAFloatingButton() {
    // A box fixed on screen would otherwise land in the image at every offset.
    func overlay(_ x: Int, _ y: Int) -> UInt32? { (30..<50).contains(x) && (30..<50).contains(y) ? noise(x, y, seed: 5) : nil }
    var stitcher = ScrollStitcher(first: frame(0, 0, overlay: overlay))
    _ = add(&stitcher, [(0, 20), (0, 40)], overlay: overlay)
    #expect(stitcher.result == bitmap(width: size, height: size + 40, page))
}

@Test func scrollStitcherKeepsASpreadsheetsPinnedHeaderRowAndFirstColumn() {
    // The header row scrolls only sideways and the first column only up and down, as in a spreadsheet.
    let headerRows = 10, firstColumns = 12
    func corner(_ x: Int, _ y: Int) -> UInt32 { noise(x, y, seed: 3) }
    func cell(_ screenX: Int, _ screenY: Int, _ ox: Int, _ oy: Int) -> UInt32 {
        if screenX < firstColumns, screenY < headerRows { return corner(screenX, screenY) }
        if screenY < headerRows { return noise(screenX + ox, screenY, seed: 11) }
        if screenX < firstColumns { return noise(screenX, screenY + oy, seed: 13) }
        return page(screenX + ox, screenY + oy)
    }
    func sheet(_ ox: Int, _ oy: Int) -> Bitmap { bitmap(width: size, height: size) { cell($0, $1, ox, oy) } }
    var stitcher = ScrollStitcher(first: sheet(0, 0))
    for (ox, oy) in [(0, 20), (0, 40), (20, 40), (40, 40), (40, 20), (40, 0)] {
        _ = stitcher.add(sheet(ox, oy))
    }
    // Wherever the canvas is, the header row is at its top and the first column at its left.
    let expected = bitmap(width: size + 40, height: size + 40) { x, y in
        if x < firstColumns, y < headerRows { return corner(x, y) }
        if y < headerRows { return noise(x, y, seed: 11) }
        if x < firstColumns { return noise(x, y, seed: 13) }
        return page(x, y)
    }
    #expect(stitcher.size.width == size + 40 && stitcher.size.height == size + 40)
    #expect(stitcher.result == expected)
}

@Test func scrollStitcherFollowsATableWhoseColumnsRepeatTheSameLabels() {
    // Every 30 columns start with the same 12-column label, so a patch of one fits in several columns; the numbers
    // between them are what pins the shift down.
    func table(_ x: Int, _ y: Int) -> UInt32 { x % 30 < 12 ? noise(x % 30, y, seed: 4) : noise(x, y) }
    var stitcher = ScrollStitcher(first: bitmap(width: size, height: size) { table($0, $1) })
    let outcomes = (1...2).map { step in stitcher.add(bitmap(width: size, height: size) { x, y in table(x + 20 * step, y) }) }
    #expect(outcomes == [.extended, .extended])
    #expect(stitcher.result == bitmap(width: size + 40, height: size, table))
}

@Test func scrollStitcherReportsAJumpAndRecoversWhenScrolledBack() {
    var stitcher = ScrollStitcher(first: frame(0, 0))
    _ = add(&stitcher, [(0, 20)])
    #expect(add(&stitcher, [(0, 120), (0, 120), (0, 120)]) == [.tooFar, .tooFar, .tooFar])
    #expect(stitcher.size.height == size + 20)
    #expect(add(&stitcher, [(0, 40)]) == [.extended])
}

@Test func scrollStitcherReportsContentThatChangesInPlace() {
    var stitcher = ScrollStitcher(first: frame(0, 0))
    _ = add(&stitcher, [(0, 20)])
    // A video fills a third of the area and shows a new picture every frame while the page stays put. The first frames
    // could still be someone letting go of the trackpad.
    func playing(_ picture: UInt32) -> Bitmap {
        frame(0, 20) { x, y in (20..<60).contains(y) && (10..<70).contains(x) ? noise(x, y, seed: picture) : nil }
    }
    let outcomes = (100..<105).map { stitcher.add(playing(UInt32($0))) }
    #expect(outcomes == [.unchanged, .unchanged, .unchanged, .moving, .moving])
    #expect(stitcher.size.height == size + 20)
}

@Test func scrollStitcherSaysWhenRepeatingContentHidesTheShift() {
    // Stripes every 20 rows look the same after a shift of 7, 27 or 47.
    func stripes(_ oy: Int) -> Bitmap {
        bitmap(width: size, height: size) { _, y in (y + oy) % 20 < 3 ? 0xffff_ffff : 0xff28_2828 }
    }
    var stitcher = ScrollStitcher(first: stripes(0))
    #expect(stitcher.add(stripes(7)) == .featureless)
    #expect(stitcher.size.height == size)
}

@Test func scrollStitcherSaysWhenThereIsNothingToFollow() {
    var stitcher = ScrollStitcher(first: bitmap(width: size, height: size) { _, _ in 0xffff_ffff })
    var next = bitmap(width: size, height: size) { _, _ in 0xffff_ffff }
    #expect(stitcher.add(next) == .unchanged)
    next = bitmap(width: size, height: size) { x, y in x == 3 && y == 3 ? 0xff00_0000 : 0xffff_ffff }
    #expect(stitcher.add(next) == .featureless)
}

@Test func scrollStitcherStopsAtTheSizeLimit() {
    var stitcher = ScrollStitcher(first: frame(0, 0), maxLength: size + 30)
    #expect(add(&stitcher, [(0, 20), (0, 40), (0, 60)]) == [.extended, .limit, .limit])
    #expect(stitcher.size.height == size + 20)
    #expect(stitcher.result == bitmap(width: size, height: size + 20, page))
}

@Test func scrollStitcherStopsAtThePixelLimit() {
    var stitcher = ScrollStitcher(first: frame(0, 0), maxPixels: size * (size + 25))
    #expect(add(&stitcher, [(0, 20), (20, 20)]) == [.extended, .limit])
    #expect(stitcher.size.width == size)
}

@Test func scrollStitcherPreviewShowsTheNewestPart() {
    var stitcher = ScrollStitcher(first: frame(0, 0))
    _ = add(&stitcher, [(0, 20), (0, 40)])
    let preview = stitcher.preview(aspect: 2)
    #expect(preview.width == size && preview.height == size / 2)
    // Centred on the last frame, which sits 40 rows down.
    #expect(preview == bitmap(width: size, height: size / 2) { page($0, $1 + 40 + size / 4) })
}
