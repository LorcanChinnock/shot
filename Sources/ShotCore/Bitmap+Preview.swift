import Foundation

// What a JPEG preview for an agent needs where there's no ImageIO thumbnail to make it: a smaller copy, and no
// transparency.

extension Bitmap {
    /// At most `maxPixelSize` on its long edge, never enlarged, each pixel the average of the block of pixels it covers.
    public func scaledDown(toFit maxPixelSize: Int) -> Bitmap {
        let long = max(width, height)
        guard long > maxPixelSize, maxPixelSize > 0 else {
            return self
        }
        let newWidth = max(1, width * maxPixelSize / long), newHeight = max(1, height * maxPixelSize / long)
        let xs = (0 ... newWidth).map { $0 * width / newWidth }, ys = (0 ... newHeight).map { $0 * height / newHeight }
        var scaled = [UInt8](repeating: 0, count: newWidth * newHeight * 4)
        pixels.withUnsafeBytes { source in
            for row in 0 ..< newHeight {
                for column in 0 ..< newWidth {
                    var r = 0, g = 0, b = 0, a = 0
                    for y in ys[row] ..< ys[row + 1] {
                        for x in xs[column] ..< xs[column + 1] {
                            let i = y * bytesPerRow + x * 4
                            r += Int(source[i])
                            g += Int(source[i + 1])
                            b += Int(source[i + 2])
                            a += Int(source[i + 3])
                        }
                    }
                    let count = (ys[row + 1] - ys[row]) * (xs[column + 1] - xs[column]), o = (row * newWidth + column) * 4
                    scaled[o] = UInt8((r + count / 2) / count)
                    scaled[o + 1] = UInt8((g + count / 2) / count)
                    scaled[o + 2] = UInt8((b + count / 2) / count)
                    scaled[o + 3] = UInt8((a + count / 2) / count)
                }
            }
        }
        return Bitmap(width: newWidth, height: newHeight, scale: scale, pixels: Data(scaled))!
    }

    /// Opaque, as if drawn over white.
    public var overWhite: Bitmap {
        var opaque = [UInt8](pixels)
        for i in stride(from: 0, to: opaque.count, by: 4) {
            let clear = 255 - Int(opaque[i + 3])
            for channel in i ..< i + 3 {
                opaque[channel] = UInt8(min(255, Int(opaque[channel]) + clear))
            }
            opaque[i + 3] = 255
        }
        return Bitmap(width: width, height: height, scale: scale, pixels: Data(opaque))!
    }
}
