import Foundation

/// One of the eight handles on a crop: its corners and the middle of its sides. Top is the smaller y.
public enum CropHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }

    /// Where the handle sits on `rect`.
    public func point(on rect: CGRect) -> CGPoint {
        CGPoint(x: movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX, y: movesTop ? rect.minY : movesBottom ? rect.maxY : rect.midY)
    }
}

/// The shape a crop is held to.
public enum CropAspect: String, CaseIterable, Sendable {
    case free, square, fourThree, sixteenNine

    /// Width over height for a crop of `size`, or `nil` for free. A ratio follows the crop's orientation: landscape
    /// while it's at least as wide as it is tall, portrait once it's taller.
    public func ratio(for size: CGSize) -> CGFloat? {
        let landscape = size.width >= size.height
        switch self {
        case .free: return nil
        case .square: return 1
        case .fourThree: return landscape ? 4 / 3 : 3 / 4
        case .sixteenNine: return landscape ? 16 / 9 : 9 / 16
        }
    }
}

/// Values an edge sticks to when it's within `tolerance` of one, such as the edges of the image.
public struct CropSnap: Equatable, Sendable {
    public var xs: [CGFloat]
    public var ys: [CGFloat]
    public var tolerance: CGFloat

    public init(xs: [CGFloat], ys: [CGFloat], tolerance: CGFloat) {
        self.xs = xs
        self.ys = ys
        self.tolerance = tolerance
    }

    func x(_ value: CGFloat) -> CGFloat { Self.snapped(value, to: xs, tolerance: tolerance) }
    func y(_ value: CGFloat) -> CGFloat { Self.snapped(value, to: ys, tolerance: tolerance) }

    private static func snapped(_ value: CGFloat, to targets: [CGFloat], tolerance: CGFloat) -> CGFloat {
        targets.filter { abs($0 - value) <= tolerance }.min { abs($0 - value) < abs($1 - value) } ?? value
    }
}

/// Resizing, moving and drawing a crop rectangle, in the image's pixels with y growing downwards.
/// `bounds` is how far the crop can reach: the image, its padding and anything drawn past it.
public enum CropGeometry {
    /// The least a crop's width or height can be, so it never collapses under its own handles.
    public static let minimumSize: CGFloat = 8

    /// The handle of `crop` within `tolerance` of `point`; a corner wins over the side it sits on.
    public static func handle(at point: CGPoint, in crop: CGRect, tolerance: CGFloat) -> CropHandle? {
        let corners = CropHandle.allCases.filter(\.isCorner)
        let sides = CropHandle.allCases.filter { !$0.isCorner }
        for handle in corners + sides {
            let at = handle.point(on: crop)
            let near: Bool
            switch handle {
            case .top, .bottom: near = abs(point.y - at.y) <= tolerance && point.x >= crop.minX - tolerance && point.x <= crop.maxX + tolerance
            case .left, .right: near = abs(point.x - at.x) <= tolerance && point.y >= crop.minY - tolerance && point.y <= crop.maxY + tolerance
            default: near = abs(point.x - at.x) <= tolerance && abs(point.y - at.y) <= tolerance
            }
            if near {
                return handle
            }
        }
        return nil
    }

    /// `crop` with `handle` dragged to `point`, kept within `bounds` and at least `minimumSize` across. A `ratio`
    /// (width over height) keeps the shape: a corner grows from the opposite corner, a side about the crop's centre.
    /// Edges snap only while the shape is free.
    public static func resize(_ crop: CGRect, handle: CropHandle, to point: CGPoint, within bounds: CGRect, ratio: CGFloat? = nil, snap: CropSnap? = nil) -> CGRect {
        let point = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        if let ratio, ratio > 0 {
            if handle.isCorner {
                let anchor = CGPoint(x: handle.movesLeft ? crop.maxX : crop.minX, y: handle.movesTop ? crop.maxY : crop.minY)
                return anchored(at: anchor, toward: point, signs: (handle.movesLeft ? -1 : 1, handle.movesTop ? -1 : 1), within: bounds, ratio: ratio) ?? crop
            }
            return resizeSide(crop, handle: handle, to: point, within: bounds, ratio: ratio)
        }
        var minX = crop.minX, maxX = crop.maxX, minY = crop.minY, maxY = crop.maxY
        if handle.movesLeft {
            minX = max(min(snap?.x(point.x) ?? point.x, maxX - minimumSize), bounds.minX)
        } else if handle.movesRight {
            maxX = min(max(snap?.x(point.x) ?? point.x, minX + minimumSize), bounds.maxX)
        }
        if handle.movesTop {
            minY = max(min(snap?.y(point.y) ?? point.y, maxY - minimumSize), bounds.minY)
        } else if handle.movesBottom {
            maxY = min(max(snap?.y(point.y) ?? point.y, minY + minimumSize), bounds.maxY)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// A side dragged with the shape held: the opposite side stays, and the crop grows or shrinks about the middle of
    /// the other axis, as far as `bounds` allows.
    private static func resizeSide(_ crop: CGRect, handle: CropHandle, to point: CGPoint, within bounds: CGRect, ratio: CGFloat) -> CGRect {
        let horizontal = handle == .left || handle == .right
        if horizontal {
            let room = 2 * min(crop.midY - bounds.minY, bounds.maxY - crop.midY) * ratio
            let wanted = handle == .right ? point.x - crop.minX : crop.maxX - point.x
            let reach = handle == .right ? bounds.maxX - crop.minX : crop.maxX - bounds.minX
            let width = min(max(wanted, minimumSize * max(1, ratio)), reach, room)
            let height = width / ratio
            return CGRect(x: handle == .right ? crop.minX : crop.maxX - width, y: crop.midY - height / 2, width: width, height: height)
        }
        let room = 2 * min(crop.midX - bounds.minX, bounds.maxX - crop.midX) / ratio
        let wanted = handle == .bottom ? point.y - crop.minY : crop.maxY - point.y
        let reach = handle == .bottom ? bounds.maxY - crop.minY : crop.maxY - bounds.minY
        let height = min(max(wanted, minimumSize * max(1, 1 / ratio)), reach, room)
        let width = height * ratio
        return CGRect(x: crop.midX - width / 2, y: handle == .bottom ? crop.minY : crop.maxY - height, width: width, height: height)
    }

    /// The rectangle of shape `ratio` with one corner at `anchor`, reaching toward `point` in the directions `signs`
    /// (1 is right or down), as large as `bounds` allows. `nil` when `bounds` leaves no room.
    private static func anchored(at anchor: CGPoint, toward point: CGPoint, signs: (x: CGFloat, y: CGFloat), within bounds: CGRect, ratio: CGFloat) -> CGRect? {
        var width = max(signs.x * (point.x - anchor.x), minimumSize)
        var height = max(signs.y * (point.y - anchor.y), minimumSize)
        if width / height > ratio {
            height = width / ratio
        } else {
            width = height * ratio
        }
        let roomX = signs.x > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let roomY = signs.y > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        let fit = min(1, roomX / width, roomY / height)
        guard fit > 0 else {
            return nil
        }
        width *= fit
        height *= fit
        return CGRect(x: signs.x > 0 ? anchor.x : anchor.x - width, y: signs.y > 0 ? anchor.y : anchor.y - height, width: width, height: height)
    }

    /// `crop` moved by `delta`, kept within `bounds`. An edge snaps when it comes near a snap value.
    public static func move(_ crop: CGRect, dx: CGFloat, dy: CGFloat, within bounds: CGRect, snap: CropSnap? = nil) -> CGRect {
        var x = crop.minX + dx, y = crop.minY + dy
        if let snap {
            let left = snap.x(x), right = snap.x(x + crop.width) - crop.width
            x = left != x ? left : right
            let top = snap.y(y), bottom = snap.y(y + crop.height) - crop.height
            y = top != y ? top : bottom
        }
        x = min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - crop.width))
        y = min(max(y, bounds.minY), max(bounds.minY, bounds.maxY - crop.height))
        return CGRect(x: x, y: y, width: crop.width, height: crop.height)
    }

    /// The rectangle dragged out from `start` to `point`, within `bounds`; with a `ratio`, the largest of that shape
    /// from `start` toward `point`. `nil` when a ratio leaves no room.
    public static func draw(from start: CGPoint, to point: CGPoint, within bounds: CGRect, ratio: CGFloat? = nil, snap: CropSnap? = nil) -> CGRect? {
        let start = CGPoint(x: min(max(start.x, bounds.minX), bounds.maxX), y: min(max(start.y, bounds.minY), bounds.maxY))
        var point = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        if let ratio, ratio > 0 {
            return anchored(at: start, toward: point, signs: (point.x >= start.x ? 1 : -1, point.y >= start.y ? 1 : -1), within: bounds, ratio: ratio)
        }
        if let snap {
            point = CGPoint(x: snap.x(point.x), y: snap.y(point.y))
        }
        return CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
    }

    /// The largest rectangle of shape `ratio` inside `rect`, centred, on whole pixels.
    public static func fit(ratio: CGFloat, in rect: CGRect) -> CGRect {
        guard ratio > 0, rect.width > 0, rect.height > 0 else {
            return rect
        }
        var width = rect.width, height = rect.height
        if width / height > ratio {
            width = (height * ratio).rounded(.down)
        } else {
            height = (width / ratio).rounded(.down)
        }
        return CGRect(x: rect.minX + ((rect.width - width) / 2).rounded(.down), y: rect.minY + ((rect.height - height) / 2).rounded(.down), width: width, height: height)
    }
}
