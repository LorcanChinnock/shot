#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(os) && canImport(UniformTypeIdentifiers)
import CoreGraphics
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// The pixels of an image placed on the canvas, kept at full resolution and stored once: annotations,
/// undo steps and copies within the editor all share the same instance rather than copying the bitmap.
/// Two are equal when they're the same stored image, so comparing documents never reads the pixels.
public final class AnnotationImage: Equatable, Codable, @unchecked Sendable {
    /// The shortest side an image can be resized down to, in canvas pixels.
    public static let minSide: CGFloat = 8

    public let id: UUID
    public let image: CGImage
    private let transparency = OSAllocatedUnfairLock<Bool?>(initialState: nil)
    /// The last crop asked for and its pixels, so redrawing a cropped image gives back the same `CGImage` and the
    /// renderer's caches, which compare images by identity, keep hitting.
    private let lastCrop = OSAllocatedUnfairLock<(crop: ImageCrop, image: CGImage)?>(initialState: nil)

    public init(_ image: CGImage, id: UUID = UUID()) {
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
    public func cropped(_ crop: ImageCrop?) -> CGImage {
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

    /// Encoded as PNG, which is lossless, so a copy pasted into another editor keeps every pixel. It calls ImageIO
    /// itself, as `ImageIOCodec` does, since `Codable` has no way to be handed an `ImageCoding`. That goes once an
    /// annotation's image is a `Bitmap`.
    public func encode(to encoder: Encoder) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw EncodingError.invalidValue(image, .init(codingPath: encoder.codingPath, debugDescription: "The image could not be encoded as PNG"))
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw EncodingError.invalidValue(image, .init(codingPath: encoder.codingPath, debugDescription: "The image could not be encoded as PNG"))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(data as Data, forKey: .png)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let png = try container.decode(Data.self, forKey: .png)
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else {
            throw DecodingError.dataCorruptedError(forKey: .png, in: container, debugDescription: "The image data could not be read")
        }
        self.image = image
    }
}
#endif
