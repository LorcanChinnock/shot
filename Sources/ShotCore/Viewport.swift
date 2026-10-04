import CoreGraphics

/// How the editor shows the canvas: a scale, and where image point (0, 0) lands in the top-left-origin view.
/// Image points are document coordinates, so a canvas that grows or is cropped doesn't move what's on screen.
public struct Viewport: Equatable, Sendable {
    /// View points per image pixel.
    public var scale: CGFloat
    /// Where image point (0, 0) lands in the view; it may be outside the view or the canvas.
    public var origin: CGPoint

    /// Space around a fitted canvas, and the most a zoomed one can be scrolled past an edge.
    public static let inset: CGFloat = 20
    /// The zooms ⌘+ and ⌘- step through, where 1 is actual size: the image at the size it was captured, in points.
    public static let zoomSteps: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]
    public static var minZoom: CGFloat { zoomSteps[0] }
    public static var maxZoom: CGFloat { zoomSteps[zoomSteps.count - 1] }

    public init(scale: CGFloat, origin: CGPoint) {
        self.scale = scale
        self.origin = origin
    }

    public func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
    }

    public func imagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }

    public func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(origin: viewPoint(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }

    /// The whole canvas, centred inside the inset and no larger than `maxScale`.
    public static func fit(_ canvas: CGRect, in size: CGSize, maxScale: CGFloat) -> Viewport {
        let fit = min((size.width - 2 * inset) / canvas.width, (size.height - 2 * inset) / canvas.height)
        return Viewport(scale: max(0.01, min(fit, maxScale)), origin: .zero).clamped(to: canvas, in: size)
    }

    /// Scaled to `scale`, keeping the image point under `point` where it is.
    public func zoomed(to scale: CGFloat, about point: CGPoint) -> Viewport {
        let anchor = imagePoint(point)
        return Viewport(scale: scale, origin: CGPoint(x: point.x - anchor.x * scale, y: point.y - anchor.y * scale))
    }

    public func panned(by offset: CGVector) -> Viewport {
        Viewport(scale: scale, origin: CGPoint(x: origin.x + offset.dx, y: origin.y + offset.dy))
    }

    /// Centres the canvas along an axis where it fits inside the inset; along one where it doesn't,
    /// stops it scrolling more than the inset past either edge.
    public func clamped(to canvas: CGRect, in size: CGSize) -> Viewport {
        func axis(origin: CGFloat, canvasMin: CGFloat, canvasLength: CGFloat, viewLength: CGFloat) -> CGFloat {
            let length = canvasLength * scale
            let start: CGFloat
            if length <= viewLength - 2 * Self.inset {
                // Rounded so the canvas edges sit on whole points.
                start = ((viewLength - length) / 2).rounded()
            } else {
                start = min(max(origin + canvasMin * scale, viewLength - Self.inset - length), Self.inset)
            }
            return start - canvasMin * scale
        }
        return Viewport(scale: scale, origin: CGPoint(
            x: axis(origin: origin.x, canvasMin: canvas.minX, canvasLength: canvas.width, viewLength: size.width),
            y: axis(origin: origin.y, canvasMin: canvas.minY, canvasLength: canvas.height, viewLength: size.height)
        ))
    }

    /// The zoom this viewport shows, relative to actual size.
    public func zoom(pixelsPerPoint: CGFloat) -> CGFloat {
        scale * pixelsPerPoint
    }

    public static func scale(forZoom zoom: CGFloat, pixelsPerPoint: CGFloat) -> CGFloat {
        zoom / pixelsPerPoint
    }

    /// The next step above `zoom`, or `zoom` itself at the top.
    public static func zoom(after zoom: CGFloat) -> CGFloat {
        zoomSteps.first { $0 > zoom + 0.001 } ?? zoom
    }

    /// The next step below `zoom`, or `zoom` itself at the bottom, so ⌘- never zooms in from a small fit.
    public static func zoom(before zoom: CGFloat) -> CGFloat {
        zoomSteps.last { $0 < zoom - 0.001 } ?? zoom
    }

    /// Keeps a pinch within the steps' range, letting it go down to `fit` when that's smaller.
    public static func clampedZoom(_ zoom: CGFloat, fit: CGFloat) -> CGFloat {
        min(max(zoom, min(minZoom, fit)), maxZoom)
    }
}
