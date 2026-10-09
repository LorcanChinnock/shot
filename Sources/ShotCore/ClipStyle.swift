import CoreImage
import CoreImage.CIFilterBuiltins
import os

extension Clip {
    /// Whether its picture has rounded corners, a shadow or a border. A plain one is drawn as it always was.
    public var isStyled: Bool { cornerRadius > 0 || !style.isEmpty }
}

extension ClipAnimation {
    /// How many times its own elevation a shadow rises to at `time`, in seconds from the clip's start: 1 at rest, and up
    /// to 2 halfway through an entrance, a move or scale keyed at the very start that settles within `presetDuration`, as
    /// Pop and Slide in make. The object seems to lift as it comes in and settle as it lands.
    public func lift(at time: Double) -> Double {
        let ends = [Self.entranceEnd(position), Self.entranceEnd(scale)].compactMap(\.self)
        let rise = ends.map { end in time > 0 && time < end ? sin(.pi * time / end) : 0 }.max() ?? 0
        return 1 + rise
    }

    /// When an entrance in `keyframes` lands: their second keyframe, if the first is at the very start, the value changes
    /// between them, and it's soon enough to be brief.
    private static func entranceEnd<Value>(_ keyframes: [Keyframe<Value>]) -> Double? {
        guard keyframes.count >= 2, keyframes[0].time <= Keyframes.tolerance, keyframes[1].value != keyframes[0].value,
              keyframes[1].time <= presetDuration + Keyframes.tolerance else {
            return nil
        }
        return keyframes[1].time
    }
}

/// Blurred clip shadows, each a grey mask of the shadow's coverage, so a frame only moves, scales and tints one rather
/// than blurring again. Keeps the few used most recently. Safe to use from any thread.
final class ClipShadowCache: Sendable {
    /// What a mask is the blur of, in canvas pixels at the scale it was made for, about the clip's upright picture.
    struct Key: Equatable, Sendable {
        var silhouette: CGRect
        var radius: CGFloat
        var blur: CGFloat
    }

    /// The mask, and where it goes in the key's pixels.
    typealias Value = (mask: CGImage, frame: CGRect)

    private let capacity: Int
    /// Most recently used first.
    private let entries = OSAllocatedUnfairLock<[(key: Key, value: Value)]>(initialState: [])

    /// Room for four scales of a three-layer shadow, so a clip that holds still blurs its shadow once.
    init(capacity: Int = 12) {
        self.capacity = capacity
    }

    /// The mask made before for `key`, or the one `make` returns, which is kept for next time.
    func mask(for key: Key, make: () -> Value?) -> Value? {
        let hit = entries.withLock { entries -> Value? in
            guard let index = entries.firstIndex(where: { $0.key == key }) else {
                return nil
            }
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
            return entry.value
        }
        if let hit {
            return hit
        }
        guard let value = make() else {
            return nil
        }
        entries.withLock { entries in
            entries.insert((key, value), at: 0)
            entries = Array(entries.prefix(capacity))
        }
        return value
    }

    var count: Int { entries.withLock { $0.count } }
}

/// Draws a clip's picture with its rounded corners, border and shadow, which grow and shrink with the clip.
enum ClipStyler {
    /// How closely the scale a shadow is blurred at follows the clip's: an eighth of a doubling, so a shadow is blurred
    /// again only as the clip grows or shrinks by about 9%, and is scaled in between.
    static let scaleSteps: CGFloat = 8
    /// How closely the lift a shadow is blurred at follows an entrance's.
    static let liftSteps: CGFloat = 8

    /// `picture`, the clip's frame already placed on the canvas, with `clip`'s corners, border and shadow and faded by its
    /// opacity, over `image`. `placement` maps the clip's upright picture, y up, onto the canvas in Core Image's
    /// coordinates, and `fit` is how much it's scaled to fit the canvas at a clip scale of 1. `lift` raises the shadow.
    /// `frame` is the frame as it comes, whose edge colour picks a hairline's and tints a glow, as an image's does.
    static func composite(
        _ picture: CIImage, of clip: Clip, frame: CIImage, placement: CGAffineTransform, fit: CGFloat, lift: Double, over image: CIImage,
        shadows: ClipShadowCache, context: CIContext
    ) -> CIImage {
        let scale = CGFloat(clip.transform.scale), opacity = CGFloat(min(max(clip.transform.opacity, 0), 1))
        guard scale > 0, fit > 0 else {
            return image
        }
        let needsEdge = clip.style.border?.kind == .hairline || clip.style.shadow?.tint == .object
        let edge = needsEdge ? edgeColor(of: frame, context: context) : nil
        let look = Look(clip, scale: scale, fit: fit)
        // From canvas pixels about the upright picture, y up, to the canvas.
        let toCanvas = CGAffineTransform(scaleX: 1 / (fit * scale), y: 1 / (fit * scale)).concatenating(placement)
        var body = picture
        if look.radius > 0 {
            let mask = roundedRect(look.rect, radius: look.radius).transformed(by: toCanvas)
            body = body.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        }
        if let border = clip.style.border {
            // A solid border tucks half a pixel under the picture, so no seam shows between them, and casts the shadow
            // with it; a hairline is a faint rim just outside the edge, light on a dark frame and dark on a light one.
            let overlap: CGFloat = border.kind == .solid ? 0.5 : 0
            let color = border.kind == .hairline ? Border.hairlineColor(edge: edge ?? RGBA(0, 0, 0)) : border.paint
            let outer = roundedRect(
                look.rect.insetBy(dx: -look.borderWidth, dy: -look.borderWidth),
                radius: look.radius > 0 ? look.radius + look.borderWidth : 0,
                color: CIColor(red: color.r, green: color.g, blue: color.b, alpha: color.a)
            )
            let inner = roundedRect(look.rect.insetBy(dx: overlap, dy: overlap), radius: max(0, look.radius - overlap))
            let ring = outer.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner]).transformed(by: toCanvas)
            body = border.castsShadow ? body.composited(over: ring) : ring.composited(over: body)
        }
        if opacity < 1 {
            body = body.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)])
        }
        guard let shadow = clip.style.shadow, opacity > 0,
              let cast = Self.shadow(shadow, of: clip, edge: edge, scale: scale, fit: fit, lift: CGFloat(lift), placement: placement, opacity: opacity, shadows: shadows, context: context)
        else {
            return body.composited(over: image)
        }
        return body.composited(over: cast.composited(over: image))
    }

    /// The shadow `clip` casts on the canvas: one cached mask per layer, scaled from the scale it was blurred at, moved
    /// down by the layer's offset and tinted. Nothing is blurred unless the clip's scale or lift moved to a new step.
    private static func shadow(
        _ shadow: Shadow, of clip: Clip, edge: RGBA?, scale: CGFloat, fit: CGFloat, lift: CGFloat, placement: CGAffineTransform, opacity: CGFloat,
        shadows: ClipShadowCache, context: CIContext
    ) -> CIImage? {
        let stepped = exp2((log2(scale) * scaleSteps).rounded() / scaleSteps)
        let lifted = 1 + ((lift - 1) * liftSteps).rounded() / liftSteps
        let caster = Look(clip, scale: stepped, fit: fit)
        var blurred = shadow, shown = shadow
        blurred.elevation *= stepped * lifted
        shown.elevation *= scale * lift
        let toCanvas = CGAffineTransform(scaleX: 1 / (fit * stepped), y: 1 / (fit * stepped)).concatenating(placement)
        // A glow takes the colour of the frame's edge, as an image's does.
        let color = shadow.color(background: nil, object: edge ?? RGBA(1, 1, 1))
        let alpha = shadow.opacity * opacity
        var result: CIImage?
        for (blur, offset) in zip(blurred.layers.map(\.blur), shown.layers.map(\.offset)) {
            let key = ClipShadowCache.Key(silhouette: caster.silhouette, radius: caster.silhouetteRadius, blur: blur)
            guard let mask = shadows.mask(for: key, make: { blurredMask(key, context: context) }) else {
                continue
            }
            let layer = CIImage(cgImage: mask.mask)
                .transformed(by: CGAffineTransform(scaleX: mask.frame.width / CGFloat(mask.mask.width), y: mask.frame.height / CGFloat(mask.mask.height))
                    .concatenating(CGAffineTransform(translationX: mask.frame.minX, y: mask.frame.minY))
                    .concatenating(toCanvas)
                    // Lit from above, so it falls down the canvas whichever way the clip is turned.
                    .concatenating(CGAffineTransform(translationX: 0, y: -offset)))
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: alpha, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: color.r, y: color.g, z: color.b, w: 0),
                ])
            result = result.map { layer.composited(over: $0) } ?? layer
        }
        return result
    }

    /// The silhouette in `key` blurred, as grey coverage over black. It's made coarser the softer it is, as the photo
    /// editor's shadows are, since a blur has no detail to lose, and never larger than 4096 pixels for a clip scaled far up.
    private static func blurredMask(_ key: ClipShadowCache.Key, context: CIContext) -> ClipShadowCache.Value? {
        let reach = (key.blur * 1.5).rounded(.up)
        let frame = key.silhouette.insetBy(dx: -reach, dy: -reach)
        let unit = min(1, 8 / max(key.blur, 1), 4096 / max(frame.width, frame.height, 1))
        let toPixels = CGAffineTransform(scaleX: unit, y: unit)
        let pixels = frame.applying(toPixels).integral
        let shape = roundedRect(key.silhouette.applying(toPixels), radius: key.radius * unit)
            .applyingGaussianBlur(sigma: Double(key.blur * unit / 2))
            .composited(over: CIImage(color: .black).cropped(to: pixels))
        guard pixels.width >= 1, pixels.height >= 1,
              let mask = context.createCGImage(shape, from: pixels, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        else {
            return nil
        }
        return (mask, CGRect(x: pixels.minX / unit, y: pixels.minY / unit, width: pixels.width / unit, height: pixels.height / unit))
    }

    /// The average colour near `frame`'s edge, an eighth of its shorter side deep all round, as an image's is read; `nil`
    /// for an empty frame. It's the whole frame's average less its middle's, so it reads back two pixels.
    static func edgeColor(of frame: CIImage, context: CIContext) -> RGBA? {
        let outer = frame.extent
        guard !outer.isInfinite, outer.width >= 1, outer.height >= 1 else {
            return nil
        }
        let depth = max(1, min(outer.width, outer.height) / 8)
        let inner = outer.insetBy(dx: depth, dy: depth)
        func average(_ rect: CGRect) -> [Float] {
            var pixel = [Float](repeating: 0, count: 4)
            guard !rect.isEmpty else {
                return pixel
            }
            let filter = CIFilter.areaAverage()
            filter.inputImage = frame
            filter.extent = rect
            if let output = filter.outputImage {
                context.render(output, toBitmap: &pixel, rowBytes: 4 * MemoryLayout<Float>.size, bounds: output.extent, format: .RGBAf, colorSpace: nil)
            }
            return pixel
        }
        let all = average(outer), middle = average(inner)
        let outerArea = outer.width * outer.height, innerArea = inner.isEmpty ? 0 : inner.width * inner.height
        let ring = outerArea - innerArea
        func channel(_ index: Int) -> CGFloat {
            (CGFloat(all[index]) * outerArea - CGFloat(middle[index]) * innerArea) / ring
        }
        let alpha = channel(3)
        guard ring > 0, alpha > 0.001 else {
            return nil
        }
        // Premultiplied, so dividing by the alpha weighs each pixel by its own, as for an image.
        return RGBA(min(max(channel(0) / alpha, 0), 1), min(max(channel(1) / alpha, 0), 1), min(max(channel(2) / alpha, 0), 1))
    }

    private static func roundedRect(_ rect: CGRect, radius: CGFloat, color: CIColor = .white) -> CIImage {
        let generator = CIFilter.roundedRectangleGenerator()
        generator.extent = rect
        generator.radius = Float(radius)
        generator.color = color
        return generator.outputImage ?? CIImage.empty()
    }

    /// Where a clip's picture and what casts its shadow are at `scale`, in canvas pixels about its upright picture's
    /// bottom-left corner, y up.
    private struct Look {
        var rect: CGRect
        var radius: CGFloat
        var borderWidth: CGFloat
        /// The picture, with a solid border round it.
        var silhouette: CGRect
        var silhouetteRadius: CGFloat

        init(_ clip: Clip, scale: CGFloat, fit: CGFloat) {
            rect = CGRect(x: 0, y: 0, width: clip.size.width * fit * scale, height: clip.size.height * fit * scale)
            radius = BoxShape.cornerRadius(clip.cornerRadius * scale, in: rect)
            let border = clip.style.border
            // A hairline stays one pixel at any scale.
            borderWidth = border.map { $0.kind == .hairline ? 1 : $0.width * scale } ?? 0
            if let border, border.castsShadow {
                silhouette = rect.insetBy(dx: -borderWidth, dy: -borderWidth)
                silhouetteRadius = radius > 0 ? radius + borderWidth : 0
            } else {
                silhouette = rect
                silhouetteRadius = radius
            }
        }
    }
}
