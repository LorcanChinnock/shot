import Foundation

/// What a placed image's own crop trims off each edge, as a fraction (0–1) of the source image's width or height.
/// Fractions survive resizing and Retina scaling: the image's rect is the size of the part left, wherever it's drawn.
public struct ImageCrop: Equatable, Hashable, Sendable, Codable {
    public var left: CGFloat
    public var top: CGFloat
    public var right: CGFloat
    public var bottom: CGFloat

    /// Nothing trimmed.
    public static let none = ImageCrop(left: 0, top: 0, right: 0, bottom: 0)

    public init(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// The crop that leaves `visible` of an image drawn whole at `full`, with `visible` kept inside `full`.
    public init(visible: CGRect, within full: CGRect) {
        guard full.width > 0, full.height > 0 else {
            self = .none
            return
        }
        let kept = visible.intersection(full)
        guard !kept.isNull else {
            self = .none
            return
        }
        left = (kept.minX - full.minX) / full.width
        top = (kept.minY - full.minY) / full.height
        right = (full.maxX - kept.maxX) / full.width
        bottom = (full.maxY - kept.maxY) / full.height
    }

    /// True when it trims nothing worth keeping, so the image is whole.
    public var isEmpty: Bool {
        [left, top, right, bottom].allSatisfy { abs($0) < 1e-6 }
    }

    /// The share of the source's width and height left.
    private var keptWidth: CGFloat { max(1 - left - right, 1e-6) }
    private var keptHeight: CGFloat { max(1 - top - bottom, 1e-6) }

    /// Where the whole image would be drawn when what's left of it is drawn at `visible`, which crop mode shows and
    /// clamps the crop to.
    public func fullRect(forVisible visible: CGRect) -> CGRect {
        let width = visible.width / keptWidth
        let height = visible.height / keptHeight
        return CGRect(x: visible.minX - left * width, y: visible.minY - top * height, width: width, height: height)
    }

    /// The part of a source image `width` by `height` pixels that's left, on whole pixels and at least one across,
    /// with a top-left origin.
    public func sourceRect(width: Int, height: Int) -> CGRect {
        let w = CGFloat(width), h = CGFloat(height)
        let minX = min(max((left * w).rounded(), 0), w - 1)
        let minY = min(max((top * h).rounded(), 0), h - 1)
        let maxX = max(min((w - right * w).rounded(), w), minX + 1)
        let maxY = max(min((h - bottom * h).rounded(), h), minY + 1)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
