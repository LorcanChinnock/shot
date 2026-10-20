import Foundation

// What `shot serve` does to a screenshot a `ScreenCapturer` took, where there's no CGImage to do it: keep part of it, and
// tell whether it has stopped changing.

extension Bitmap {
    /// The pixels `rect` covers, which must be whole and inside the image, as `AgentTarget.pixels` gives them; `nil`
    /// otherwise.
    public func cropped(to rect: CGRect) -> Bitmap? {
        let x = Int(rect.minX), y = Int(rect.minY), newWidth = Int(rect.width), newHeight = Int(rect.height)
        guard x >= 0, y >= 0, newWidth > 0, newHeight > 0, x + newWidth <= width, y + newHeight <= height else {
            return nil
        }
        if x == 0, y == 0, newWidth == width, newHeight == height {
            return self
        }
        var cropped = Data(capacity: newWidth * newHeight * 4)
        for row in y ..< y + newHeight {
            let start = pixels.startIndex + row * bytesPerRow + x * 4
            cropped.append(pixels[start ..< start + newWidth * 4])
        }
        return Bitmap(width: newWidth, height: newHeight, scale: scale, pixels: cropped)
    }

    /// The image at most 64 pixels on its long edge, as one grey level a pixel, for `StableWait` to compare.
    public var grayThumbnail: [UInt8] {
        let small = scaledDown(toFit: 64)
        return small.pixels.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: 4).map { (i: Int) -> UInt8 in
                let red = Int(bytes[i]) * 299, green = Int(bytes[i + 1]) * 587, blue = Int(bytes[i + 2]) * 114
                return UInt8((red + green + blue) / 1000)
            }
        }
    }
}
