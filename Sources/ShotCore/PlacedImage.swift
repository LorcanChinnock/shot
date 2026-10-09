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

extension EditorDocument {
    /// The size, in canvas pixels, to place an image at whose pixels are `scale` per point on a document
    /// whose are `documentScale` per point. An image of lower density is scaled up to show at the same
    /// size in points; one of the same or higher density keeps one image pixel per canvas pixel, since
    /// shrinking it would throw pixels away.
    public static func placementSize(of image: CGImage, scale: CGFloat, documentScale: CGFloat) -> CGSize {
        let factor = max(1, documentScale / max(scale, 1))
        return CGSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
    }

    /// Where an image goes when no drop chose a spot: `gap` to the right of the canvas, level with its top,
    /// so screenshots line up side by side. A crop edge never grows, so if the right one is a crop the image
    /// goes below instead, and if both are it's centred on the canvas.
    public func rectBesideCanvas(_ size: CGSize, gap: CGFloat) -> CGRect {
        let canvas = canvasRect, image = fullRect
        let origin: CGPoint
        if canvas.maxX >= image.maxX {
            origin = CGPoint(x: canvas.maxX + gap, y: canvas.minY)
        } else if canvas.maxY >= image.maxY {
            origin = CGPoint(x: canvas.minX, y: canvas.maxY + gap)
        } else {
            origin = CGPoint(x: canvas.midX - size.width / 2, y: canvas.midY - size.height / 2)
        }
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }

    /// Places `image` on whole pixels, centred on `point` or beside the canvas when there's none, grows the
    /// canvas to hold it, and returns its annotation's id. See `placementSize` for the size it's given.
    @discardableResult
    public mutating func addImage(_ image: CGImage, scale: CGFloat, documentScale: CGFloat, centeredAt point: CGPoint?, margin: CGFloat) -> UUID {
        let size = Self.placementSize(of: image, scale: scale, documentScale: documentScale)
        let rect: CGRect
        if let point {
            rect = CGRect(origin: CGPoint(x: (point.x - size.width / 2).rounded(), y: (point.y - size.height / 2).rounded()), size: size)
        } else {
            rect = rectBesideCanvas(size, gap: margin)
        }
        let annotation = Annotation(kind: .image(AnnotationImage(image), rect: rect), color: RGBA(0, 0, 0), lineWidth: 0)
        annotations.append(annotation)
        grow(toFit: annotation, margin: margin)
        return annotation.id
    }
}
