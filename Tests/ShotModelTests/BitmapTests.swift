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
