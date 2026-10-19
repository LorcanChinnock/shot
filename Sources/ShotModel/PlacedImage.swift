#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Synchronization

/// The pixels of an image placed on the canvas, kept at full resolution and stored once: annotations,
/// undo steps and copies within the editor all share the same instance rather than copying the bitmap.
/// Two are equal when they're the same stored image, so comparing documents never reads the pixels.
public final class AnnotationImage: Equatable, Codable, Sendable {
    /// The shortest side an image can be resized down to, in canvas pixels.
    public static let minSide: CGFloat = 8

    public let id: UUID
    public let image: PlatformImage
    private let transparency = Mutex<Bool?>(nil)
    /// The last crop asked for and its pixels, so redrawing a cropped image gives back the same image and the
    /// renderer's caches, which compare images by identity, keep hitting.
    private let lastCrop = Mutex<(crop: ImageCrop, image: PlatformImage)?>(nil)

    public init(_ image: PlatformImage, id: UUID = UUID()) {
        self.id = id
        self.image = image
    }

    /// Whether any of its pixels is see-through, which an outline needs. It's read the first time it's asked, then kept.
    public var hasTransparency: Bool {
        transparency.withLock { known in
            if let known {
                return known
            }
            let transparent = image.hasTransparentPixels
            known = transparent
            return transparent
        }
    }

    /// The part of the image `crop` leaves; the whole image when there's no crop.
    public func cropped(_ crop: ImageCrop?) -> PlatformImage {
        guard let crop, !crop.isEmpty else {
            return image
        }
        return lastCrop.withLock { last in
            if let last, last.crop == crop {
                return last.image
            }
            let cropped = image.cropping(to: crop.sourceRect(width: image.width, height: image.height)) ?? image
            last = (crop, cropped)
            return cropped
        }
    }

    public static func == (lhs: AnnotationImage, rhs: AnnotationImage) -> Bool {
        lhs.id == rhs.id
    }

    private enum CodingKeys: String, CodingKey {
        case id, png
    }

    /// Encoded as PNG, which is lossless, so a copy pasted into another editor keeps every pixel. The encoder's
    /// `userInfo` gives the codec, under `pngCodec`; without one it throws, rather than drop the image.
    public func encode(to encoder: Encoder) throws {
        guard let codec = encoder.userInfo[.pngCodec] as? any PNGCoding else {
            throw EncodingError.invalidValue(image, .init(codingPath: encoder.codingPath, debugDescription: "No PNG codec in the encoder's userInfo"))
        }
        guard let png = codec.png(from: image) else {
            throw EncodingError.invalidValue(image, .init(codingPath: encoder.codingPath, debugDescription: "The image could not be encoded as PNG"))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(png, forKey: .png)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let codec = decoder.userInfo[.pngCodec] as? any PNGCoding else {
            throw DecodingError.dataCorruptedError(forKey: .png, in: container, debugDescription: "No PNG codec in the decoder's userInfo")
        }
        id = try container.decode(UUID.self, forKey: .id)
        let png = try container.decode(Data.self, forKey: .png)
        guard let image = codec.image(fromPNG: png) else {
            throw DecodingError.dataCorruptedError(forKey: .png, in: container, debugDescription: "The image data could not be read")
        }
        self.image = image
    }
}
