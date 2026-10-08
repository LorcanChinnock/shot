import Foundation
import CoreGraphics

public enum Geometry {
    /// Converts between AppKit global space (bottom-left origin) and CoreGraphics global space (top-left origin); the conversion is its own inverse.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - (rect.minY + rect.height), width: rect.width, height: rect.height)
    }

    public static func flip(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    public static func normalized(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// The largest square with a corner at `anchor` that extends toward `point`.
    public static func square(from anchor: CGPoint, to point: CGPoint) -> CGRect {
        fitted(from: anchor, to: point, ratio: 1)
    }

    /// The largest rect of `ratio` (long side over short side) with a corner at `anchor` that extends toward `point`,
    /// landscape when the drag is wider than tall and portrait otherwise.
    public static func fitted(from anchor: CGPoint, to point: CGPoint, ratio: CGFloat) -> CGRect {
        let dx = abs(point.x - anchor.x), dy = abs(point.y - anchor.y)
        let widthOverHeight = dx >= dy ? ratio : 1 / ratio
        let width = min(dx, dy * widthOverHeight)
        let height = width / widthOverHeight
        let corner = CGPoint(
            x: anchor.x + (point.x >= anchor.x ? width : -width),
            y: anchor.y + (point.y >= anchor.y ? height : -height)
        )
        return normalized(from: anchor, to: corner)
    }

    /// `point` moved onto the nearest of the eight directions 45° apart from `anchor`, keeping its distance.
    public static func snapped(from anchor: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        let length = hypot(dx, dy)
        return CGPoint(x: anchor.x + length * cos(angle), y: anchor.y + length * sin(angle))
    }

    /// Converts a global AppKit rect to display-local, top-left-origin points.
    public static func displayLocalTopLeft(_ rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX - screenFrame.minX, y: screenFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a rect in a bottom-left-origin view (points) to a top-left-origin pixel rect for cropping.
    public static func pixelRect(forViewRect rect: CGRect, viewHeight: CGFloat, scale: CGFloat) -> CGRect {
        CGRect(
            x: (rect.minX * scale).rounded(),
            y: ((viewHeight - rect.maxY) * scale).rounded(),
            width: (rect.width * scale).rounded(),
            height: (rect.height * scale).rounded()
        )
    }

    public static func evenFloor(_ value: CGFloat) -> Int {
        let integer = Int(value.rounded(.down))
        return integer - integer % 2
    }
}

/// An on-screen window in CoreGraphics global space.
public struct WindowInfo: Equatable, Sendable {
    public let windowID: CGWindowID
    public let frame: CGRect
    public let ownerPID: pid_t

    public init(windowID: CGWindowID, frame: CGRect, ownerPID: pid_t) {
        self.windowID = windowID
        self.frame = frame
        self.ownerPID = ownerPID
    }

    /// `windows` must be ordered front to back, as `CGWindowListCopyWindowInfo` returns them.
    public static func topmost(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.frame.contains(point) }
    }

    /// Keeps normal-layer windows of other apps that are at least 40 × 40 pt.
    public static func parse(_ list: [[String: Any]], excludingPID: pid_t) -> [WindowInfo] {
        list.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != excludingPID,
                  let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 40, bounds.height >= 40
            else {
                return nil
            }
            return WindowInfo(windowID: number, frame: bounds, ownerPID: pid)
        }
    }
}
