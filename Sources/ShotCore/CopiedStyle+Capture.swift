import CoreGraphics
import Foundation

public extension CopiedStyle {
    /// `image`, a new capture of `scale` pixels per point, with this style on it over `background`, as Use this style
    /// for new captures copies it; `nil` when the style changes nothing. A window captured with the macOS shadow,
    /// `windowShadow`, takes no style, so it's `nil` for one.
    /// Its canvas, if it has one, goes round the image, and `desktopPicture` is what a Desktop fill draws.
    func styledCapture(_ image: CGImage, scale: CGFloat, background: RGBA?, windowShadow: Bool = false, desktopPicture: CGImage? = nil) -> CGImage? {
        var doc = EditorDocument(base: image, background: background)
        doc.hasWindowShadow = windowShadow
        doc.desktopPicture = desktopPicture
        doc.applyNewCaptureStyle(self, scale: scale, margin: 0)
        guard !doc.captureStyle.isEmpty || doc.captureCornerRadius > 0 || canvas != nil else {
            return nil
        }
        return AnnotationRenderer.flatten(doc)
    }
}

public extension EditorDocument {
    /// Puts the style Use for new captures saved on the screenshot: its shadow, border and corners, then its canvas.
    mutating func applyNewCaptureStyle(_ style: CopiedStyle, scale: CGFloat, margin: CGFloat) {
        pasteStyle(style, to: [.capture], scale: scale, margin: margin)
        if let canvas = style.canvas {
            applyCanvas(canvas, scale: scale)
        }
    }
}
