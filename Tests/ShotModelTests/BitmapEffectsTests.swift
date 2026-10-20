import Foundation
import Testing
@testable import ShotModel

/// A `width` × `height` bitmap, top row first, each pixel from `pixel(x, y)`.
private func bitmap(width: Int, height: Int, _ pixel: (Int, Int) -> [UInt8]) -> Bitmap {
    var pixels = Data()
    for y in 0..<height {
        for x in 0..<width {
            pixels += pixel(x, y)
        }
    }
    return Bitmap(width: width, height: height, pixels: pixels)!
}

/// Each pixel's red, top row first.
private func reds(_ bitmap: Bitmap) -> [[Int]] {
    (0..<bitmap.height).map { y in (0..<bitmap.width).map { Int(bitmap[$0, y].r) } }
}

@Test func pixelateTakesTheColourAtTheMiddleOfEachBlockLinedUpWithTheRegion() throws {
    // Red counts across in tens, and green down.
    let image = bitmap(width: 4, height: 4) { x, y in [UInt8(x * 10), UInt8(y * 10), 0, 255] }
    // Each block's middle falls between four pixels, which count equally.
    let all = try #require(image.pixelated(region: CGRect(x: 0, y: 0, width: 4, height: 4), blockSize: 2))
    #expect(reds(all) == [[5, 5, 25, 25], [5, 5, 25, 25], [5, 5, 25, 25], [5, 5, 25, 25]])
    #expect(all[0, 0].g == 5 && all[0, 3].g == 25 && all[3, 3].a == 255)

    // From one pixel in: the blocks start there, and the last one's middle is past the image, where the edge repeats.
    let inset = try #require(image.pixelated(region: CGRect(x: 1, y: 0, width: 3, height: 4), blockSize: 2))
    #expect(reds(inset)[0] == [15, 15, 30])
}

@Test func pixelateRegionsCountUpFromTheBottom() throws {
    let image = bitmap(width: 4, height: 4) { _, y in [0, UInt8(y * 10), 0, 255] }
    // The bottom two rows, 20 and 30, which are the last two from the top.
    let bottom = try #require(image.pixelated(region: CGRect(x: 0, y: 0, width: 4, height: 2), blockSize: 2))
    #expect(bottom.height == 2 && bottom[0, 0].g == 25 && bottom[3, 1].g == 25)
}

@Test func pixelateGivesAFractionalBlockThePixelsWhoseMiddlesItHolds() throws {
    let image = bitmap(width: 8, height: 1) { x, _ in [UInt8(x * 10), 0, 0, 255] }
    // Blocks 2.5 wide hold the middles 0.5 and 1.5, then 2.5, 3.5 and 4.5, then 5.5 and 6.5, then 7.5. Their own
    // middles are at 1.25, 3.75, 6.25 and 8.75, a quarter of the way from one pixel's middle to the next, or past the edge.
    let blocks = try #require(image.pixelated(region: CGRect(x: 0, y: 0, width: 8, height: 1), blockSize: 2.5))
    #expect(reds(blocks)[0] == [8, 8, 33, 33, 33, 58, 58, 70])
}

@Test func pixelateTakesOnlyTheMiddleOfABlock() throws {
    // One white pixel in each corner of an 8 × 8 block, which its middle doesn't reach.
    let corners = bitmap(width: 8, height: 8) { x, y in [0, 7].contains(x) && [0, 7].contains(y) ? [255, 255, 255, 255] : [0, 0, 0, 255] }
    let block = try #require(corners.pixelated(region: CGRect(x: 0, y: 0, width: 8, height: 8), blockSize: 8))
    #expect(Set(reds(block).joined()) == [0])
    let middle = bitmap(width: 8, height: 8) { x, y in x == 4 && y == 4 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
    #expect(try #require(middle.pixelated(region: CGRect(x: 0, y: 0, width: 8, height: 8), blockSize: 8))[0, 0].r == 64)
}

@Test func pixelateOfNoWholePixelIsNothing() {
    let image = bitmap(width: 4, height: 4) { _, _ in [0, 0, 0, 255] }
    #expect(image.pixelated(region: CGRect(x: 1, y: 1, width: 0, height: 3), blockSize: 2) == nil)
    #expect(image.blurredBlocks(region: .zero, radius: 4) == nil)
}

@Test func blurredBlocksHideStripesTheWidthOfAPixel() throws {
    // The sharpest detail there is, which a blur alone would leave faintly striped.
    // The region is further from the image's edges than the blur reaches, so the edge blocks don't show.
    let stripes = bitmap(width: 80, height: 60) { x, _ in x % 2 == 0 ? [0, 0, 0, 255] : [255, 255, 255, 255] }
    let hidden = try #require(stripes.blurredBlocks(region: CGRect(x: 25, y: 20, width: 30, height: 20), radius: 6))
    #expect(hidden.width == 30 && hidden.height == 20)
    let levels = reds(hidden).joined()
    #expect(levels.allSatisfy { (126...130).contains($0) })
}

@Test func aBlurKeepsAnEvenColourAsItIsUpToTheEdges() {
    let teal = bitmap(width: 30, height: 20) { _, _ in [20, 140, 130, 255] }
    #expect(teal.blurred(radius: 2) == teal)
    #expect(teal.blurred(radius: 8) == teal)
}

@Test func aBlurBlendsInLinearLight() {
    // Black meeting white blurs to more than the 128 that blending the stored levels would give.
    let edge = bitmap(width: 60, height: 4) { x, _ in x < 30 ? [0, 0, 0, 255] : [255, 255, 255, 255] }
    let blurred = edge.blurred(radius: 6)
    let row = reds(blurred)[2]
    // Halfway in linear light is 188 in sRGB; the two pixels either side of the edge straddle it.
    #expect(row[29] < 188 && row[30] > 188)
    #expect(row[0] == 0 && row[59] == 255)
    #expect(zip(row, row.dropFirst()).allSatisfy { $0 <= $1 })
}

@Test func aBlurKeepsColoursPremultiplied() {
    let dot = bitmap(width: 9, height: 9) { x, y in x == 4 && y == 4 ? [200, 0, 100, 200] : [0, 0, 0, 0] }
    let blurred = dot.blurred(radius: 1.5)
    for y in 0..<9 {
        for x in 0..<9 {
            let p = blurred[x, y]
            #expect(p.r <= p.a && p.b <= p.a)
        }
    }
    #expect(blurred[4, 4].a < 200 && blurred[4, 4].a > blurred[4, 5].a && blurred[4, 5].a == blurred[5, 4].a)
}

@Test func aMaskBlurBlursTheLevelsThemselves() {
    let mask = bitmap(width: 40, height: 40) { x, _ in x < 20 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
    let blurred = mask.blurredMask(radius: 4)
    let row = reds(blurred)[20]
    // Halfway, as plain levels, is 128, so the pixels either side of the edge sum to about 255.
    #expect(abs(row[19] + row[20] - 255) <= 1)
    #expect(row[0] == 255 && row[39] == 0)
    #expect(blurred[10, 10].g == blurred[10, 10].r && blurred[10, 10].a == 255)
}

@Test(arguments: [3.0, 12])
func aMaskBlurOfAnEvenLevelChangesNothing(radius: CGFloat) {
    let grey = bitmap(width: 25, height: 15) { _, _ in [90, 90, 90, 255] }
    #expect(grey.blurredMask(radius: radius) == grey)
}

@Test func aGrownMaskGrowsByADiscOfTheRadiusRoundedDown() {
    let dot = bitmap(width: 1, height: 1) { _, _ in [255, 255, 255, 255] }
    let grown = dot.grownMask(radius: 2.6)
    #expect(grown.width == 7 && grown.height == 7)
    let white = reds(grown).map { $0.map { $0 == 255 ? "#" : "." }.joined() }
    #expect(white == [
        ".......",
        "...#...",
        "..###..",
        ".#####.",
        "..###..",
        "...#...",
        ".......",
    ])
    #expect(grown[0, 0].a == 255)
}

@Test func aGrownMaskKeepsTheMostAlphaNearby() {
    // Half clear on the left, opaque at the right edge.
    let image = bitmap(width: 5, height: 1) { x, _ in x == 0 ? [64, 0, 0, 128] : x == 4 ? [0, 0, 0, 255] : [0, 0, 0, 0] }
    let grown = image.grownMask(radius: 1)
    #expect(reds(grown)[1] == [128, 128, 128, 0, 255, 255, 255])
    #expect(reds(grown)[0] == [0, 128, 0, 0, 0, 255, 0])
}

@Test func aGrownMaskOfLessThanAPixelOnlyPadsTheShape() {
    let dot = bitmap(width: 2, height: 1) { x, _ in x == 0 ? [255, 255, 255, 255] : [0, 0, 0, 0] }
    let grown = dot.grownMask(radius: 0.5)
    #expect(reds(grown) == [[0, 0, 0, 0], [0, 255, 0, 0], [0, 0, 0, 0]])
}
