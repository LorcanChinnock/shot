#if canImport(CoreGraphics)
import CoreGraphics

extension Annotation {
    /// How far past where it draws it reads what's under it, on `base`; `nil` when it only paints over it.
    /// A layer that reads acts on everything drawn under it, so this is all the renderer needs to know to draw it in order.
    func backdropReach(base: CGImage) -> CGFloat? {
        switch kind {
        case .pixelate:
            AnnotationRenderer.redactionSize(self, base: base)
        case .blur:
            AnnotationRenderer.redactionSize(self, base: base) * 4
        case let .spotlight(_, style):
            // A Gaussian blur spreads about three times its radius; a darkening reads only the pixel it darkens.
            style.effect == .blur ? style.blurRadius(forImageLength: AnnotationRenderer.longerSide(of: base)) * 3 : 0
        case .arrow, .line, .shape, .highlight, .text, .counter, .note, .freehand, .marker, .image:
            nil
        }
    }
}
#endif
