import Foundation

public extension CopiedStyle {
    /// `image`, a new capture of `scale` pixels per point, with this style on it over `background`, as Use this style
    /// for new captures copies it; `nil` when the style changes nothing. A window captured with the macOS shadow,
    /// `windowShadow`, takes no style, so it's `nil` for one. It's drawn on a new `canvasType` canvas.
    func styledCapture(_ image: PlatformImage, scale: CGFloat, background: RGBA?, windowShadow: Bool = false, canvasType: any Canvas.Type) -> PlatformImage? {
        var doc = EditorDocument(base: image, background: background)
        doc.hasWindowShadow = windowShadow
        doc.pasteStyle(self, to: [.capture], scale: scale, margin: 0, shaper: canvasType.shaper)
        guard !doc.captureStyle.isEmpty || doc.captureCornerRadius > 0 else {
            return nil
        }
        return AnnotationRenderer.flatten(doc, canvasType: canvasType)
    }
}
