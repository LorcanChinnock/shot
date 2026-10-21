import Foundation

/// An area built with the arrow keys instead of a drag, so the capture overlay works without a mouse.
/// Rects are in the overlay's view space; `bounds` is the display.
public enum KeyboardArea {
    public static let minimumSide: CGFloat = 8
    public static let step: CGFloat = 10
    public static let fineStep: CGFloat = 1

    /// The first area an arrow key creates: a rect centred on `point`, held to `ratio` (width over height) if given.
    public static func start(at point: CGPoint, ratio: CGFloat?, in bounds: CGRect) -> CGRect {
        var width = min(240, bounds.width)
        var height = min(ratio.map { width / $0 } ?? 160, bounds.height)
        if let ratio, height * ratio < width {
            width = height * ratio
        }
        height = ratio.map { width / $0 } ?? height
        let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        return moved(rect, dx: 0, dy: 0, in: bounds)
    }

    /// `rect` shifted by `dx`, `dy`, kept inside `bounds`.
    public static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat, in bounds: CGRect) -> CGRect {
        var result = rect.offsetBy(dx: dx, dy: dy)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }

    /// `rect` grown by `dw` wide and `dh` tall (negative shrinks) from its bottom-left corner, which stays put.
    /// Held to `ratio` when given (the changed side leads), to at least `minimumSide`, and inside `bounds`.
    public static func resized(_ rect: CGRect, dw: CGFloat, dh: CGFloat, ratio: CGFloat?, in bounds: CGRect) -> CGRect {
        let maxWidth = bounds.maxX - rect.minX
        let maxHeight = bounds.maxY - rect.minY
        var width = rect.width + dw
        var height = rect.height + dh
        if let ratio {
            // Landscape or portrait, whichever the rect already is; the arrow that moved the long side leads.
            let portrait = rect.height > rect.width
            let shape = portrait ? 1 / ratio : ratio
            if dw != 0 {
                width = rect.width + dw
                height = width / shape
            } else {
                height = rect.height + dh
                width = height * shape
            }
            let fit = min(1, maxWidth / width, maxHeight / height)
            width *= fit
            height *= fit
            let floor = max(1, minimumSide / min(width, height))
            if floor > 1 {
                width *= floor
                height *= floor
            }
        } else {
            width = min(max(width, minimumSide), maxWidth)
            height = min(max(height, minimumSide), maxHeight)
        }
        return CGRect(x: rect.minX, y: rect.minY, width: width, height: height)
    }
}
