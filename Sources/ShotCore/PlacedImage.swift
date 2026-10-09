import CoreGraphics
import Foundation
import os

/// The pixels of an image placed on the canvas, kept at full resolution and stored once: annotations,
/// undo steps and copies within the editor all share the same instance rather than copying the bitmap.
/// Two are equal when they're the same stored image, so comparing documents never reads the pixels.
public final class AnnotationImage: Equatable, Codable, @unchecked Sendable {
    /// The shortest side an image can be resized down to, in canvas pixels.
    public static let minSide: CGFloat = 8

    public let id: UUID
    public let image: CGImage
    private let transparency = OSAllocatedUnfairLock<Bool?>(initialState: nil)

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

    public static func == (lhs: AnnotationImage, rhs: AnnotationImage) -> Bool {
        lhs.id == rhs.id
    }

    private enum CodingKeys: String, CodingKey {
        case id, png
    }

    /// Encoded as PNG, which is lossless, so a copy pasted into another editor keeps every pixel.
    public func encode(to encoder: Encoder) throws {
        guard let png = ImageCodec.data(from: image, scale: 1) else {
            throw EncodingError.invalidValue(image, .init(codingPath: encoder.codingPath, debugDescription: "The image could not be encoded as PNG"))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(png, forKey: .png)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        guard let image = ImageCodec.image(from: try container.decode(Data.self, forKey: .png)) else {
            throw DecodingError.dataCorruptedError(forKey: .png, in: container, debugDescription: "The image data could not be read")
        }
        self.image = image
    }
}
