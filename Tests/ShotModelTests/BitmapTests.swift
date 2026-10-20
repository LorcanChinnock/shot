import Foundation
import Testing
@testable import ShotModel

@Test func aBitmapNeedsExactlyFourBytesForEachPixel() {
    #expect(Bitmap(width: 2, height: 3, pixels: Data(count: 24)) != nil)
    #expect(Bitmap(width: 2, height: 3, pixels: Data(count: 23)) == nil)
    #expect(Bitmap(width: 2, height: 3, pixels: Data(count: 28)) == nil)
    #expect(Bitmap(width: 0, height: 3, pixels: Data()) == nil)
}

@Test func aBitmapsPixelsRunTopRowFirst() throws {
    // 2×2: red, green on top; blue, half-clear white below.
    let pixels = Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 128, 128, 128, 128])
    let bitmap = try #require(Bitmap(width: 2, height: 2, scale: 2, pixels: pixels))
    #expect(bitmap.bytesPerRow == 8)
    #expect(bitmap.scale == 2)
    #expect(bitmap[1, 0] == (0, 255, 0, 255))
    #expect(bitmap[0, 1] == (0, 0, 255, 255))
    #expect(bitmap[1, 1] == (128, 128, 128, 128))
}

@Test func aBitmapReadsPixelsFromASliceOfData() throws {
    let whole = Data([9, 9, 9, 9] + [1, 2, 3, 4])
    let bitmap = try #require(Bitmap(width: 1, height: 1, pixels: whole.dropFirst(4)))
    #expect(bitmap[0, 0] == (1, 2, 3, 4))
}

@Test func aBitmapsVisibleBoundsHoldEveryPixelThatIsntFullyClear() throws {
    // 4×3, clear but for a faint pixel at (1, 0) and a solid one at (2, 1).
    var pixels = Data(count: 48)
    pixels[1 * 4 + 3] = 1
    pixels[1 * 16 + 2 * 4 + 3] = 255
    let bitmap = try #require(Bitmap(width: 4, height: 3, pixels: pixels))
    #expect(bitmap.visibleBounds == CGRect(x: 1, y: 0, width: 2, height: 2))
    #expect(try #require(Bitmap(width: 4, height: 3, pixels: Data(count: 48))).visibleBounds == nil)
    // The leftmost pixel in the last row, the rightmost in the first, and a clear row between them.
    var corners = Data(count: 48)
    corners[3 * 4 + 3] = 9
    corners[2 * 16 + 0 * 4 + 3] = 9
    #expect(try #require(Bitmap(width: 4, height: 3, pixels: corners)).visibleBounds == CGRect(x: 0, y: 0, width: 4, height: 3))
    #expect(try #require(Bitmap(width: 1, height: 1, pixels: Data([0, 0, 0, 255]))).visibleBounds == CGRect(x: 0, y: 0, width: 1, height: 1))
}

@Test func aBitmapCropsToWholePixelsInsideIt() throws {
    // 3×2, each pixel's red byte its index.
    let pixels = Data((0 ..< 6).flatMap { [UInt8($0), 0, 0, 255] })
    let bitmap = try #require(Bitmap(width: 3, height: 2, scale: 2, pixels: pixels))
    let cropped = try #require(bitmap.cropped(to: CGRect(x: 1, y: 0, width: 2, height: 2)))
    #expect(cropped.width == 2 && cropped.height == 2 && cropped.scale == 2)
    #expect(cropped[0, 0].r == 1 && cropped[1, 0].r == 2 && cropped[0, 1].r == 4 && cropped[1, 1].r == 5)
    #expect(bitmap.cropped(to: CGRect(x: 0, y: 0, width: 3, height: 2)) == bitmap)
    #expect(bitmap.cropped(to: CGRect(x: 2, y: 0, width: 2, height: 1)) == nil)
    #expect(bitmap.cropped(to: CGRect(x: 0, y: 0, width: 0, height: 1)) == nil)
}

@Test func aBitmapsGrayThumbnailIsAtMost64PixelsOfLevels() throws {
    let white = try #require(Bitmap(width: 200, height: 100, pixels: Data(repeating: 255, count: 200 * 100 * 4)))
    let thumbnail = white.grayThumbnail
    #expect(thumbnail.count == 64 * 32)
    #expect(thumbnail.allSatisfy { $0 == 255 })
    let red = try #require(Bitmap(width: 1, height: 1, pixels: Data([255, 0, 0, 255])))
    #expect(red.grayThumbnail == [76])
}
