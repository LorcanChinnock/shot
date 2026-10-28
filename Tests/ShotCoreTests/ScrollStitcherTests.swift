import Foundation
import Testing

@testable import ShotCore

/// A page of `rows` rows, each a different grey with a few columns, so every row is unique.
private func page(rows: Int, width: Int = 6) -> [[UInt8]] {
    (0..<rows).map { y in (0..<width).map { x in UInt8((y * 7 + x * 3 + y / 13) % 251) } }
}

private func bitmap(_ rows: [[UInt8]]) -> Bitmap {
    var data = Data()
    for row in rows {
        for v in row {
            data.append(contentsOf: [v, v &+ 1, v &+ 2, 255])
        }
    }
    return Bitmap(width: rows[0].count, height: rows.count, pixels: data)!
}

/// The area showing `content[offset..<offset + view]` between a fixed header and footer.
private func frame(_ content: [[UInt8]], at offset: Int, view: Int, header: [[UInt8]] = [], footer: [[UInt8]] = []) -> Bitmap {
    bitmap(header + Array(content[offset..<offset + view]) + footer)
}

@Test func scrollStitcherJoinsFramesIntoOnePage() {
    let content = page(rows: 400)
    var stitcher = ScrollStitcher(first: frame(content, at: 0, view: 100))
    #expect(stitcher.add(frame(content, at: 40, view: 100)) == .appended(40))
    #expect(stitcher.add(frame(content, at: 90, view: 100)) == .appended(50))
    #expect(stitcher.result == bitmap(Array(content[0..<190])))
}

@Test func scrollStitcherKeepsStickyHeaderAndFooterOnce() {
    let content = page(rows: 400, width: 6)
    let header = (0..<10).map { _ in [UInt8](repeating: 200, count: 5) + [UInt8(1)] }
    let footer = (0..<8).map { _ in [UInt8](repeating: 99, count: 5) + [UInt8(2)] }
    var stitcher = ScrollStitcher(first: frame(content, at: 0, view: 80, header: header, footer: footer))
    _ = stitcher.add(frame(content, at: 30, view: 80, header: header, footer: footer))
    _ = stitcher.add(frame(content, at: 60, view: 80, header: header, footer: footer))
    #expect(stitcher.result == bitmap(header + Array(content[0..<140]) + footer))
}

@Test func scrollStitcherAddsNothingWhenScrollingBack() {
    let content = page(rows: 400)
    var stitcher = ScrollStitcher(first: frame(content, at: 0, view: 100))
    _ = stitcher.add(frame(content, at: 50, view: 100))
    #expect(stitcher.add(frame(content, at: 20, view: 100)) == .unchanged)
    #expect(stitcher.add(frame(content, at: 20, view: 100)) == .unchanged)
    #expect(stitcher.add(frame(content, at: 100, view: 100)) == .appended(50))
    #expect(stitcher.result == bitmap(Array(content[0..<200])))
}

@Test func scrollStitcherReportsAJumpAndRecoversWhenScrolledBack() {
    let content = page(rows: 600)
    var stitcher = ScrollStitcher(first: frame(content, at: 0, view: 100))
    _ = stitcher.add(frame(content, at: 30, view: 100))
    #expect(stitcher.add(frame(content, at: 300, view: 100)) == .tooFar)
    #expect(stitcher.length == 130)
    #expect(stitcher.add(frame(content, at: 60, view: 100)) == .appended(30))
}

@Test func scrollStitcherReportsContentThatChangesInPlace() {
    let content = page(rows: 400)
    var stitcher = ScrollStitcher(first: frame(content, at: 0, view: 100))
    _ = stitcher.add(frame(content, at: 30, view: 100))
    var video = Array(content[30..<130])
    for y in 20..<70 {
        video[y] = video[y].map { $0 &+ 100 }
    }
    #expect(stitcher.add(bitmap(video)) == .moving)
}

@Test func scrollStitcherIgnoresRepeatedFramesAndStopsAtTheLimit() {
    let content = page(rows: 400)
    var stitcher = ScrollStitcher(first: frame(content, at: 0, view: 100), maxLength: 160)
    #expect(stitcher.add(frame(content, at: 0, view: 100)) == .unchanged)
    #expect(stitcher.add(frame(content, at: 50, view: 100)) == .appended(50))
    #expect(stitcher.add(frame(content, at: 100, view: 100)) == .limit)
    #expect(stitcher.length == 160)
    #expect(stitcher.add(frame(content, at: 150, view: 100)) == .limit)
    #expect(stitcher.result == bitmap(Array(content[0..<160])))
}

@Test func scrollStitcherStitchesSideways() {
    let content = page(rows: 300, width: 5)
    let wide = { (offset: Int) in bitmap(Array(content[offset..<offset + 80])).transposed() }
    var stitcher = ScrollStitcher(first: wide(0), axis: .horizontal)
    #expect(stitcher.add(wide(35)) == .appended(35))
    #expect(stitcher.result == bitmap(Array(content[0..<115])).transposed())
}
