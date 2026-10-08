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
    /// With a `ratio` (width over height), the rect keeps that shape: corners pivot on the opposite corner, edges grow around their centre line.
    public func adjust(_ rect: CGRect, by delta: CGVector, in bounds: CGRect, minSize: CGFloat = 80, ratio: CGFloat? = nil) -> CGRect {
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
        let free = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard let ratio else {
            return free
        }
        return fitted(free, from: rect, in: bounds, minSize: minSize, ratio: ratio)
    }

    private func fitted(_ free: CGRect, from rect: CGRect, in bounds: CGRect, minSize: CGFloat, ratio: CGFloat) -> CGRect {
        let movesLeft = [.topLeft, .left, .bottomLeft].contains(self)
        let movesRight = [.topRight, .right, .bottomRight].contains(self)
        let movesDown = [.bottomLeft, .bottom, .bottomRight].contains(self)
        let movesUp = [.topLeft, .top, .topRight].contains(self)
        let movesX = movesLeft || movesRight, movesY = movesDown || movesUp

        let maxWidth = movesLeft ? rect.maxX - bounds.minX
            : movesRight ? bounds.maxX - rect.minX
            : 2 * min(rect.midX - bounds.minX, bounds.maxX - rect.midX)
        let maxHeight = movesDown ? rect.maxY - bounds.minY
            : movesUp ? bounds.maxY - rect.minY
            : 2 * min(rect.midY - bounds.minY, bounds.maxY - rect.midY)

        var width = movesX && movesY ? Geometry.fitted(free.size, ratio: ratio).width : movesX ? free.width : free.height * ratio
        width = min(max(width, minSize, minSize * ratio), maxWidth, maxHeight * ratio)
        let height = width / ratio

        let x = movesLeft ? rect.maxX - width : movesRight ? rect.minX : rect.midX - width / 2
        let y = movesDown ? rect.maxY - height : movesUp ? rect.minY : rect.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
