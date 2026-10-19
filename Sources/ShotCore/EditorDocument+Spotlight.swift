#if canImport(CoreGraphics)
import CoreGraphics

extension EditorDocument {
    /// The part of the image, and of what's drawn under the lowest spotlight, that the spotlights dim: all of it
    /// outside every hard-edged spotlight, never the rest of the padding. `softSpotlights` fade it further.
    /// `nil` when there are no spotlights. One with no area, such as a straight drag, dims nothing.
    public func spotlightDimPath(shaper: any TextShaper) -> CGPath? {
        var lit: CGPath?
        var hasSpotlight = false
        var isAboveDim = false
        let below = CGMutablePath()
        for annotation in annotations where !annotation.isHidden {
            guard case let .spotlight(rect, style) = annotation.kind else {
                if !isAboveDim, case let painted = annotation.paintedBounds(shaper: shaper), !painted.isNull {
                    below.addRect(painted)
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
            let shape = style.shape.path(in: rect, cornerRadius: annotation.cornerRadius).cgPath
            lit = lit?.union(shape) ?? shape
        }
        guard hasSpotlight else {
            return nil
        }
        let radius = clampedCaptureCornerRadius
        let image = CGPath(roundedRect: captureRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let dimmable = below.isEmpty ? image : below.union(image)
        return lit.map { dimmable.subtracting($0) } ?? dimmable
    }
}
#endif
