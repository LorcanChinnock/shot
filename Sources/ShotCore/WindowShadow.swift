import CoreGraphics

/// The window inside a window capture taken with the macOS shadow: the capture has a see-through margin where the shadow
/// fades out, around the window itself, which is opaque.
public enum WindowShadow {
    /// Alpha at or above this counts as the window. The shadow never gets this solid, even right beside the window.
    static let opaque: UInt8 = 250

    /// The window's own bounds in `image`, in pixels from the top left: the smallest rectangle holding every opaque pixel.
    /// The rounded corners are see-through, but each edge is opaque along its length, so they're inside. `nil` when nothing
    /// is opaque, or when everything to the edges is, so there's no shadow margin.
    public static func body(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else {
            return nil
        }
        // A bitmap context's memory runs from the top row down; alpha is the fourth byte of each pixel.
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = pixels + y * width * 4
            for x in 0..<width where row[x * 4 + 3] >= opaque {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else {
            return nil
        }
        let body = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return body == CGRect(x: 0, y: 0, width: width, height: height) ? nil : body
    }
}
