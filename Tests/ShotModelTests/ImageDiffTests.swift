import Foundation
import Testing
@testable import ShotModel

/// A `width` by `height` RGBA image of one grey, with `paint` setting chosen pixels to another colour.
private func image(width: Int, height: Int, grey: UInt8 = 200, paint: [(x: Int, y: Int, rgba: [UInt8])] = []) -> [UInt8] {
    var bytes = [UInt8](repeating: grey, count: width * height * 4)
    for i in stride(from: 3, to: bytes.count, by: 4) {
        bytes[i] = 255
    }
    for (x, y, rgba) in paint {
        bytes.replaceSubrange((y * width + x) * 4 ..< (y * width + x) * 4 + 4, with: rgba)
    }
    return bytes
}

/// A mask with 1 at each of `points`.
private func mask(width: Int, height: Int, _ points: [(Int, Int)]) -> [UInt8] {
    var mask = [UInt8](repeating: 0, count: width * height)
    for (x, y) in points {
        mask[y * width + x] = 1
    }
    return mask
}

/// Every point in the box `x, y, width, height`.
private func box(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> [(Int, Int)] {
    (y ..< y + height).flatMap { row in (x ..< x + width).map { ($0, row) } }
}

@Test func identicalImagesHaveNoChanges() {
    let a = image(width: 10, height: 6)
    let changes = ImageDiff.changes(a, a, width: 10, height: 6, bytesPerRow: 40, threshold: 0)
    #expect(changes.allSatisfy { $0 == 0 })
    #expect(ImageDiff.regions(in: changes, width: 10, height: 6).isEmpty)
}

@Test func theThresholdIgnoresSmallColourShiftsButNotRealChanges() {
    let a = image(width: 4, height: 1)
    let b = image(width: 4, height: 1, paint: [(1, 0, [210, 200, 200, 255]), (2, 0, [200, 200, 240, 255]), (3, 0, [200, 200, 200, 0])])
    #expect(ImageDiff.changes(a, b, width: 4, height: 1, bytesPerRow: 16) == [0, 0, 1, 1])
    #expect(ImageDiff.changes(a, b, width: 4, height: 1, bytesPerRow: 16, threshold: 0) == [0, 1, 1, 1])
    #expect(ImageDiff.changes(a, b, width: 4, height: 1, bytesPerRow: 16, threshold: 1) == [0, 0, 0, 0])
}

@Test func paddingAtTheEndOfEachRowIsIgnored() {
    // Two pixels a row, in rows of 12 bytes; the last 4 of each row differ but aren't pixels.
    let a: [UInt8] = [1, 1, 1, 255, 2, 2, 2, 255, 0, 0, 0, 0, 3, 3, 3, 255, 4, 4, 4, 255, 0, 0, 0, 0]
    var b = a
    b[8] = 255
    b[20] = 255
    b[12] = 200
    #expect(ImageDiff.changes(a, b, width: 2, height: 2, bytesPerRow: 12) == [0, 0, 1, 0])
}

@Test func aBlockOfChangesIsOneTightRegion() {
    let changed = mask(width: 100, height: 60, box(30, 20, 15, 10))
    #expect(ImageDiff.regions(in: changed, width: 100, height: 60) == [ImageDiff.Region(x: 30, y: 20, width: 15, height: 10)])
}

@Test func changesCloseTogetherShareARegion() {
    // Letters of a word a few pixels apart, spanning cells, are one box.
    let letters = [box(10, 10, 3, 8), box(16, 10, 3, 8), box(22, 12, 3, 6)].flatMap { $0 }
    let regions = ImageDiff.regions(in: mask(width: 60, height: 40, letters), width: 60, height: 40)
    #expect(regions == [ImageDiff.Region(x: 10, y: 10, width: 15, height: 8)])
}

@Test func changesFarApartAreSeparateRegionsInReadingOrder() {
    let points = box(70, 5, 4, 4) + box(5, 50, 6, 2) + box(5, 5, 2, 2)
    let regions = ImageDiff.regions(in: mask(width: 100, height: 60, points), width: 100, height: 60)
    #expect(regions.map(\.rect) == [[5, 5, 2, 2], [70, 5, 4, 4], [5, 50, 6, 2]])
}

@Test func boxesThatOverlapMerge() {
    // An L whose box takes in a separate dot inside its corner.
    let points = box(0, 0, 40, 2) + box(0, 0, 2, 40) + box(30, 30, 1, 1)
    let regions = ImageDiff.regions(in: mask(width: 50, height: 50, points), width: 50, height: 50)
    #expect(regions == [ImageDiff.Region(x: 0, y: 0, width: 40, height: 40)])
}

@Test func aGapOfZeroStillJoinsTouchingPixels() {
    let points = box(0, 0, 3, 1) + box(3, 1, 1, 1) + box(9, 9, 1, 1)
    let regions = ImageDiff.regions(in: mask(width: 10, height: 10, points), width: 10, height: 10, gap: 0)
    #expect(regions.map(\.rect) == [[0, 0, 4, 2], [9, 9, 1, 1]])
}

@Test func onlyTheLargestRegionsAreListedStillInReadingOrder() {
    let regions = [
        ImageDiff.Region(x: 0, y: 0, width: 1, height: 1),
        ImageDiff.Region(x: 0, y: 10, width: 5, height: 5),
        ImageDiff.Region(x: 0, y: 20, width: 2, height: 2),
        ImageDiff.Region(x: 0, y: 30, width: 4, height: 4),
    ]
    #expect(ImageDiff.largest(regions, limit: 2).map(\.y) == [10, 30])
    #expect(ImageDiff.largest(regions, limit: 9) == regions)
}
