import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// An image the editor's model holds: a capture, or a picture placed on it. The model only measures, crops and asks
/// about transparency; drawing and file formats belong to the platform.
public protocol ModelImage: AnyObject, Sendable {
    /// The image a crop gives, the same type. Not `Self`, which `CGImage`, an open class, can't promise.
    associatedtype Cropped: ModelImage

    var width: Int { get }
    var height: Int { get }
    /// The pixels in `rect`, in pixels from the top left, rounded out to whole pixels and kept within the image; `nil`
    /// when that leaves none.
    func cropping(to rect: CGRect) -> Cropped?
    /// Whether any of its pixels is see-through.
    var hasTransparentPixels: Bool { get }
}

#if canImport(CoreGraphics)
/// The image the model holds: on a Mac, a `CGImage`, so a capture keeps its own colour space, such as Display P3, and
/// the renderer draws it as it is.
public typealias PlatformImage = CGImage

extension CGImage: ModelImage {
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
#else
/// The image the model holds: where there's no CoreGraphics, a `Bitmap`.
public typealias PlatformImage = BitmapImage
#endif

/// A `Bitmap` as a `ModelImage`. It's a class, as `CGImage` is, so caches can compare images by identity.
public final class BitmapImage: ModelImage {
    public let bitmap: Bitmap

    public init(_ bitmap: Bitmap) {
        self.bitmap = bitmap
    }

    public var width: Int { bitmap.width }
    public var height: Int { bitmap.height }

    public func cropping(to rect: CGRect) -> BitmapImage? {
        let kept = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !kept.isNull, !kept.isEmpty else {
            return nil
        }
        let x = Int(kept.minX), y = Int(kept.minY), keptWidth = Int(kept.width), keptHeight = Int(kept.height)
        var pixels = Data(capacity: keptWidth * keptHeight * 4)
        for row in y..<y + keptHeight {
            let start = bitmap.pixels.startIndex + row * bitmap.bytesPerRow + x * 4
            pixels.append(bitmap.pixels[start..<start + keptWidth * 4])
        }
        return Bitmap(width: keptWidth, height: keptHeight, scale: bitmap.scale, pixels: pixels).map(BitmapImage.init)
    }

    /// Reads every alpha byte, stopping at the first that isn't opaque.
    public var hasTransparentPixels: Bool {
        bitmap.pixels.withUnsafeBytes { bytes in
            stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] < 255 }
        }
    }
}

/// Writes the images the model holds as PNG and reads them back, for the projects and copies that save them. A
/// `Codable` image can't be handed one, so it reads it from the coder's `userInfo` under `pngCodec`; encoding an image
/// without one throws. ShotCore's `ImageCoding` is one.
public protocol PNGCoding: Sendable {
    func png(from image: PlatformImage) -> Data?
    func image(fromPNG data: Data) -> PlatformImage?
}

extension CodingUserInfoKey {
    /// The `PNGCoding` a model image encodes and decodes through.
    public static let pngCodec = CodingUserInfoKey(rawValue: "dev.lorcan.Shot.pngCodec")!
}
