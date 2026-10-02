import CoreGraphics

/// Drag handles around a recording region, in AppKit space (bottom-left origin).
public enum RegionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move

    /// Where the handle sits on `rect`.
    public func anchor(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .top, .move: CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// Applies a drag of `delta` to `rect`, keeping it inside `bounds` and at least `minSize`.
    public func adjust(_ rect: CGRect, by delta: CGVector, in bounds: CGRect, minSize: CGFloat = 80) -> CGRect {
        if self == .move {
            var moved = rect.offsetBy(dx: delta.dx, dy: delta.dy)
            moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
            moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
            return moved
        }
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if [.topLeft, .left, .bottomLeft].contains(self) {
            minX = min(max(minX + delta.dx, bounds.minX), maxX - minSize)
        }
        if [.topRight, .right, .bottomRight].contains(self) {
            maxX = max(min(maxX + delta.dx, bounds.maxX), minX + minSize)
        }
        if [.bottomLeft, .bottom, .bottomRight].contains(self) {
            minY = min(max(minY + delta.dy, bounds.minY), maxY - minSize)
        }
        if [.topLeft, .top, .topRight].contains(self) {
            maxY = max(min(maxY + delta.dy, bounds.maxY), minY + minSize)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
