import CoreGraphics

/// The side of a scrolling capture's image that is still growing: where the person last scrolled into new content.
public enum ScrollFrontier: Equatable, Sendable {
    case top, bottom, left, right

    public var isVertical: Bool { self == .top || self == .bottom }

    /// The frontier after an update that took the image from `oldSize` to `newSize` with the area at `viewport`, in
    /// pixels. Growth puts the frontier on the side the area is against; an update that didn't grow keeps `previous`.
    public static func after(_ previous: ScrollFrontier, oldSize: CGSize, newSize: CGSize, viewport: CGRect) -> ScrollFrontier {
        if newSize.height > oldSize.height {
            return viewport.minY < 0.5 && viewport.maxY < newSize.height - 0.5 ? .top : .bottom
        }
        if newSize.width > oldSize.width {
            return viewport.minX < 0.5 && viewport.maxX < newSize.width - 0.5 ? .left : .right
        }
        return previous
    }
}

/// Where the scrolling capture panel draws its preview, in points within a box of a fixed size: the image so far,
/// the hatched room past the frontier that isn't covered yet, and the yellow edge on the area's frontier side.
public struct ScrollPreviewLayout: Equatable, Sendable {
    /// Where the image so far goes.
    public var image: CGRect
    /// The room past the frontier marked "Not yet"; nil when the image can't grow or there's no room.
    public var notYet: CGRect?
    /// The line on the area's frontier side; nil before there's an image.
    public var edge: CGRect?

    /// - Parameters:
    ///   - size: The image so far, in pixels.
    ///   - viewport: Where the area is within the image, in pixels.
    ///   - box: The preview's size, in points.
    ///   - reserve: Points kept free past the frontier while the image can still grow, so "Not yet" always shows.
    ///   - growing: Whether the image can still grow; false once it reaches the size limit.
    ///   - edgeWidth: The edge's thickness, in points.
    public init(size: CGSize, viewport: CGRect, frontier: ScrollFrontier, box: CGSize, reserve: CGFloat, growing: Bool, edgeWidth: CGFloat = 2) {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else {
            image = .zero
            notYet = growing ? CGRect(origin: .zero, size: box) : nil
            edge = nil
            return
        }
        let vertical = frontier.isVertical
        let kept = growing ? reserve : 0
        let room = CGSize(width: max(1, box.width - (vertical ? 0 : kept)), height: max(1, box.height - (vertical ? kept : 0)))
        let scale = min(room.width / size.width, room.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        // Centred across the frontier, and against the side away from it along it.
        var origin = CGPoint(x: (box.width - fitted.width) / 2, y: (box.height - fitted.height) / 2)
        switch frontier {
        case .bottom: origin.y = 0
        case .top: origin.y = box.height - fitted.height
        case .right: origin.x = 0
        case .left: origin.x = box.width - fitted.width
        }
        image = CGRect(origin: origin, size: fitted)

        let spare: CGRect = switch frontier {
        case .bottom: CGRect(x: 0, y: image.maxY, width: box.width, height: box.height - image.maxY)
        case .top: CGRect(x: 0, y: 0, width: box.width, height: image.minY)
        case .right: CGRect(x: image.maxX, y: 0, width: box.width - image.maxX, height: box.height)
        case .left: CGRect(x: 0, y: 0, width: image.minX, height: box.height)
        }
        notYet = growing && spare.width >= 1 && spare.height >= 1 ? spare : nil

        let area = CGRect(x: origin.x + viewport.minX * scale, y: origin.y + viewport.minY * scale, width: viewport.width * scale, height: viewport.height * scale)
        let half = edgeWidth / 2
        let line: CGRect = switch frontier {
        case .bottom: CGRect(x: area.minX, y: area.maxY - half, width: area.width, height: edgeWidth)
        case .top: CGRect(x: area.minX, y: area.minY - half, width: area.width, height: edgeWidth)
        case .right: CGRect(x: area.maxX - half, y: area.minY, width: edgeWidth, height: area.height)
        case .left: CGRect(x: area.minX - half, y: area.minY, width: edgeWidth, height: area.height)
        }
        // Kept inside the box, so a line at the very edge isn't cut in half.
        edge = CGRect(
            x: min(max(line.minX, 0), box.width - line.width),
            y: min(max(line.minY, 0), box.height - line.height),
            width: min(line.width, box.width),
            height: min(line.height, box.height)
        )
    }
}
