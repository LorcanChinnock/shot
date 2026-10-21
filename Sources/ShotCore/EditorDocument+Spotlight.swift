import CoreGraphics
import Foundation

extension EditorDocument {
    /// What the spotlights dim, in parts: the painted bounds of what's drawn under the lowest spotlight, the image as it's
    /// rounded, and the hard-edged spotlights, which cut out what they cover. `nil` when there are no spotlights. One with
    /// no area, such as a straight drag, cuts out nothing.
    private func spotlightDimParts(shaper: any TextShaper) -> (below: [CGRect], image: CanvasPath, lit: [CanvasPath])? {
        var lit: [CanvasPath] = []
        var hasSpotlight = false
        var isAboveDim = false
        var below: [CGRect] = []
        for annotation in annotations where !annotation.isHidden {
            guard case let .spotlight(rect, style) = annotation.kind else {
                if !isAboveDim, case let painted = annotation.paintedBounds(shaper: shaper), !painted.isNull {
                    below.append(painted)
                }
                continue
            }
            isAboveDim = true
            guard !rect.isEmpty else {
                continue
            }
            hasSpotlight = true
            guard style.softEdge == 0 else {
                continue
            }
            lit.append(style.shape.path(in: rect, cornerRadius: annotation.cornerRadius))
        }
        guard hasSpotlight else {
            return nil
        }
        return (below, CanvasPath(roundedRect: captureRect, cornerRadius: clampedCaptureCornerRadius), lit)
    }

    /// The part of the image, and of what's drawn under the lowest spotlight, that the spotlights dim: all of it
    /// outside every hard-edged spotlight, never the rest of the padding. `softSpotlights` fade it further.
    /// `nil` when there are no spotlights. One with no area, such as a straight drag, dims nothing.
    public func spotlightDimPath(shaper: any TextShaper) -> CGPath? {
        guard let parts = spotlightDimParts(shaper: shaper) else {
            return nil
        }
        let below = CGMutablePath()
        for rect in parts.below {
            below.addRect(rect)
        }
        let image = parts.image.cgPath
        let dimmable = below.isEmpty ? image : below.union(image)
        let lit = parts.lit.reduce(nil as CGPath?) { lit, shape in lit?.union(shape.cgPath) ?? shape.cgPath }
        return lit.map { dimmable.subtracting($0) } ?? dimmable
    }

    /// The area `spotlightDimPath` dims, for a canvas that can't add or subtract paths: white where it dims and black
    /// where it doesn't, drawn on a grey `canvasType` canvas at `scale` pixels to a unit. `frame` is the smallest rect on
    /// whole pixels holding all it dims, which the mask covers, its top row at the frame's min y. `nil` when it dims nothing.
    func spotlightDimMask(shaper: any TextShaper, canvasType: any Canvas.Type, scale: CGFloat) -> (mask: PlatformImage, frame: CGRect)? {
        guard let parts = spotlightDimParts(shaper: shaper) else {
            return nil
        }
        let reach = parts.below.reduce(captureRect) { $0.union($1) }
        let pixels = CGRect(x: reach.minX * scale, y: reach.minY * scale, width: reach.width * scale, height: reach.height * scale).integral
        guard pixels.width >= 1, pixels.height >= 1,
              let canvas = canvasType.init(width: Int(pixels.width), height: Int(pixels.height), format: .grey)
        else {
            return nil
        }
        // Top-left origin, as the document has it, so the image's top row is the frame's min y.
        canvas.translateBy(x: 0, y: pixels.height)
        canvas.scaleBy(x: scale, y: -scale)
        canvas.translateBy(x: -pixels.minX / scale, y: -pixels.minY / scale)
        canvas.setFillColor(RGBA(1, 1, 1))
        canvas.fill(parts.image)
        for rect in parts.below {
            canvas.fill(rect)
        }
        canvas.setFillColor(RGBA(0, 0, 0))
        for shape in parts.lit {
            canvas.fill(shape)
        }
        guard let dimmed = canvas.makeBitmap()?.litBounds, let mask = canvas.makeImage()?.cropping(to: dimmed) else {
            return nil
        }
        let frame = CGRect(x: pixels.minX + dimmed.minX, y: pixels.minY + dimmed.minY, width: dimmed.width, height: dimmed.height)
        return (mask, CGRect(x: frame.minX / scale, y: frame.minY / scale, width: frame.width / scale, height: frame.height / scale))
    }
}

private extension Bitmap {
    /// The smallest rect holding every pixel that isn't black, top-left origin; `nil` when all are. It reads only red,
    /// which holds the level of a grey canvas.
    var litBounds: CGRect? {
        var left = width, right = -1, top = height, bottom = -1
        let width = width, height = height, bytesPerRow = bytesPerRow
        pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for y in 0..<height {
                for x in 0..<width where bytes[y * bytesPerRow + x * 4] != 0 {
                    left = min(left, x)
                    right = max(right, x)
                    top = min(top, y)
                    bottom = max(bottom, y)
                }
            }
        }
        guard right >= 0 else {
            return nil
        }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }
}
