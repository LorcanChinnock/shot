import CoreGraphics
import Foundation
import os

/// A Style popover tile's picture: what the popover styles, drawn small with a preset on it, so each tile shows how the
/// selection would look.
public enum StyleThumbnail {
    /// What's drawn: a picture, such as the screenshot, a placed image or a video clip's frame, or a mark or text.
    public enum Subject: @unchecked Sendable {
        case image(CGImage)
        case annotation(Annotation)
    }

    /// How large a style is drawn on the tile, in tile points per point of the style. Drawn at full size, a shadow or
    /// border would swamp a picture this small; at this size it reads as it does on the canvas.
    static let styleScale: CGFloat = 0.2
    /// How much of the tile the picture fills, leaving room for its shadow and border.
    static let fill: CGFloat = 0.62

    /// `subject` with `style` and `cornerRadius`, both in points, fitted into a tile `size` points big at `pixelsPerPoint`.
    /// `background` tints a shadow as the canvas's does. `nil` when there's nothing to draw.
    public static func render(
        _ subject: Subject, style: ObjectStyle, cornerRadius: CGFloat, size: CGSize, pixelsPerPoint: CGFloat, background: RGBA? = nil
    ) -> CGImage? {
        let pixels = CGSize(width: (size.width * pixelsPerPoint).rounded(), height: (size.height * pixelsPerPoint).rounded())
        guard pixels.width >= 1, pixels.height >= 1, let ctx = CGContext(
            data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.translateBy(x: 0, y: pixels.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        // The picture sits a little high, since a shadow mostly falls below it.
        let box = CGRect(
            x: pixels.width * (1 - fill) / 2, y: pixels.height * (1 - fill) * 0.4,
            width: pixels.width * fill, height: pixels.height * fill
        )
        // The style in tile pixels.
        let tileStyle = styleScale * pixelsPerPoint
        switch subject {
        case let .image(image):
            // Shrunk to the tile first, so a hairline stays a pixel and a large screenshot isn't drawn small each time.
            let fitted = shrunk(image, toFit: box.size)
            let rect = centred(CGSize(width: fitted.width, height: fitted.height), in: box)
            let radius = BoxShape.cornerRadius(cornerRadius * tileStyle, in: rect)
            AnnotationRenderer.drawImage(fitted, in: rect, cornerRadius: radius, style: style.scaled(by: tileStyle), shadowBackground: background, ctx: ctx)
        case var .annotation(annotation):
            let bounds = annotation.bounds
            guard !bounds.isNull, bounds.width > 0 || bounds.height > 0 else {
                return nil
            }
            let fit = min(box.width / max(bounds.width, 1), box.height / max(bounds.height, 1))
            let rect = centred(CGSize(width: bounds.width * fit, height: bounds.height * fit), in: box)
            ctx.translateBy(x: rect.minX, y: rect.minY)
            ctx.scaleBy(x: fit, y: fit)
            ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
            // The context scales by `fit`, so the style is drawn that much larger in the annotation's own pixels.
            annotation.style = style.scaled(by: tileStyle / fit)
            AnnotationRenderer.draw(annotation, base: placeholder, background: background, in: ctx)
        }
        return ctx.makeImage()
    }

    private static func centred(_ size: CGSize, in box: CGRect) -> CGRect {
        CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height).integral
    }

    private static let placeholder: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    /// The image last shrunk and the copy made, since every tile of a popover draws the same one. It holds on to the
    /// screenshot, so the popover lets go of it with `forgetShrunk` as it closes.
    private static let lastShrunk = OSAllocatedUnfairLock<(source: CGImage, box: CGSize, image: CGImage)?>(initialState: nil)

    public static func forgetShrunk() {
        lastShrunk.withLock { $0 = nil }
    }

    /// `image` scaled to fit `box`, in pixels, keeping its shape; as it is when it already fits.
    static func shrunk(_ image: CGImage, toFit box: CGSize) -> CGImage {
        let factor = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
        guard factor < 1 else {
            return image
        }
        if let known = lastShrunk.withLock({ $0.flatMap { $0.source === image && $0.box == box ? $0.image : nil } }) {
            return known
        }
        let small = ImageCodec.downscaled(image, scale: 1 / factor)
        lastShrunk.withLock { $0 = (image, box, small) }
        return small
    }
}
