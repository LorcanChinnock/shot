import Foundation

/// An image as plain pixels, so code that runs without CoreGraphics can read and make one: 8-bit RGBA, premultiplied,
/// in sRGB, top row first, with no padding between rows. `scale` is pixels per point, 2 for a Retina capture, as the
/// file's DPI says.
public struct Bitmap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var scale: CGFloat
    /// `bytesPerRow × height` bytes.
    public let pixels: Data

    public var bytesPerRow: Int { width * 4 }

    /// `nil` unless the size is at least 1×1 and `pixels` holds exactly that many pixels.
    public init?(width: Int, height: Int, scale: CGFloat = 1, pixels: Data) {
        guard width > 0, height > 0, pixels.count == width * height * 4 else {
            return nil
        }
        self.width = width
        self.height = height
        self.scale = scale
        self.pixels = pixels
    }

    /// The red, green, blue and alpha bytes of the pixel `x` across and `y` down.
    public subscript(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        precondition(x >= 0 && x < width && y >= 0 && y < height)
        let i = pixels.startIndex + y * bytesPerRow + x * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }
}

extension Bitmap {
    /// The smallest rect holding every pixel that isn't fully clear, top-left origin; `nil` when every pixel is. It reads
    /// in from each edge only as far as the first such pixel, so a picture with a thin clear border costs little.
    public var visibleBounds: CGRect? {
        pixels.withUnsafeBytes { bytes -> CGRect? in
            func visible(_ x: Int, _ y: Int) -> Bool { bytes[y * bytesPerRow + x * 4 + 3] != 0 }
            func hasVisible(row y: Int) -> Bool { (0..<width).contains { visible($0, y) } }
            guard let top = (0..<height).first(where: hasVisible), let bottom = (top..<height).last(where: hasVisible) else {
                return nil
            }
            var left = width, right = -1
            for y in top...bottom {
                if let x = (0..<left).first(where: { visible($0, y) }) {
                    left = x
                }
                if let x = (right + 1..<width).last(where: { visible($0, y) }) {
                    right = x
                }
            }
            return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        }
    }
}
