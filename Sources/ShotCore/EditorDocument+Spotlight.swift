import CoreGraphics
import Foundation

extension EditorDocument {
    /// What the spotlights dim, in parts: the painted bounds of what's drawn under the lowest spotlight, the image as it's
    /// rounded, and the hard-edged spotlights, which cut out what they cover. `nil` when there are no spotlights. One with
    /// no area, such as a straight drag, cuts out nothing.
    private func spotlightDimParts() -> (below: [CGRect], image: CGPath, lit: [CGPath])? {
        var lit: [CGPath] = []
        var hasSpotlight = false
        var isAboveDim = false
        var below: [CGRect] = []
        for annotation in annotations where !annotation.isHidden {
            guard case let .spotlight(rect, style) = annotation.kind else {
                if !isAboveDim, case let painted = annotation.paintedBounds, !painted.isNull {
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
        return (below, CGPath(roundedRect: captureRect, cornerWidth: clampedCaptureCornerRadius, cornerHeight: clampedCaptureCornerRadius, transform: nil), lit)
    }

    /// The part of the image, and of what's drawn under the lowest spotlight, that the spotlights dim: all of it
    /// outside every hard-edged spotlight, never the rest of the padding. `softSpotlights` fade it further.
    /// `nil` when there are no spotlights. One with no area, such as a straight drag, dims nothing.
    public var spotlightDimPath: CGPath? {
        guard let parts = spotlightDimParts() else {
            return nil
        }
        let below = CGMutablePath()
        for rect in parts.below {
            below.addRect(rect)
        }
        let image = parts.image
        let dimmable = below.isEmpty ? image : below.union(image)
        let lit = parts.lit.reduce(nil as CGPath?) { lit, shape in lit?.union(shape) ?? shape }
        return lit.map { dimmable.subtracting($0) } ?? dimmable
    }
}
