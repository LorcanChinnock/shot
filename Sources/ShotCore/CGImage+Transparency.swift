import Foundation
import CoreGraphics

extension CGImage {
    /// Read from a 64×64 copy. An image without alpha isn't, without reading it.
    public var hasTransparentPixels: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        let side = 64
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = ctx.data else {
            return false
        }
        // Averaging keeps a thin see-through edge visible in the small copy, where picking single pixels could miss it.
        ctx.interpolationQuality = .medium
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: side, height: side))
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        return (0..<side * side).contains { bytes[$0 * 4 + 3] < 255 }
    }
}
