import CoreGraphics
import Foundation

public enum CameraBubbleSize: String, CaseIterable, Sendable {
    case small, medium, large

    public var diameter: CGFloat {
        switch self {
        case .small: 160
        case .medium: 220
        case .large: 300
        }
    }

    public var next: CameraBubbleSize {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// One size larger (`by: 1`) or smaller (`by: -1`), stopping at the ends rather than wrapping, as the keyboard and
    /// VoiceOver step it. `nil` when there's no size that way.
    public func stepped(by step: Int) -> CameraBubbleSize? {
        let all = Self.allCases
        let index = all.firstIndex(of: self)! + step
        return all.indices.contains(index) ? all[index] : nil
    }

    /// The size whose diameter is closest to `diameter`, so dragging the handle snaps to the sizes Settings offers.
    public static func nearest(toDiameter diameter: CGFloat) -> CameraBubbleSize {
        allCases.min { abs($0.diameter - diameter) < abs($1.diameter - diameter) }!
    }

    /// Largest size that still fits inside `region` with `inset` on each side, or `nil` if none fits.
    public static func fitting(_ preferred: CameraBubbleSize, in region: CGRect, inset: CGFloat) -> CameraBubbleSize? {
        let room = min(region.width, region.height) - inset * 2
        return allCases.reversed().first { $0.diameter <= preferred.diameter && $0.diameter <= room }
    }
}

/// How the bubble is drawn (spec › Camera bubble): the camera clipped to a circle, a 3 pt white ring outside it, and a
/// 16 pt round handle on its lower edge while checking before recording.
public enum CameraBubbleStyle {
    /// From the recorded area's edges to the circle, as on the boards.
    public static let inset: CGFloat = 18
    public static let ringWidth: CGFloat = 3
    /// The 1 pt ink line Increase Contrast adds outside the white ring, so the bubble reads on a white page.
    public static let contrastEdgeWidth: CGFloat = 1
    public static let handleDiameter: CGFloat = 16
    public static let handleEdgeWidth: CGFloat = 1.5
    /// The square around the handle's centre that starts a resize, larger than the handle so it's easy to grab.
    public static let handleHitSize: CGFloat = 28

    /// How far the window reaches outside the circle: the ring and Increase Contrast's line.
    public static var margin: CGFloat { ringWidth + contrastEdgeWidth }
}

public enum CameraBubbleLayout {
    /// Where the resize handle sits on the circle `circle`: on its lower edge, at 45°, on the side facing the middle of
    /// `region`, so it points at the room the bubble can grow into. AppKit space, bottom-left origin.
    public static func handleCenter(for circle: CGRect, in region: CGRect) -> CGPoint {
        let offset = circle.width / 2 / 2.squareRoot()
        let towardRight = circle.midX <= region.midX
        return CGPoint(x: circle.midX + (towardRight ? offset : -offset), y: circle.midY - offset)
    }

    /// The size a handle drag at `pointer` asks for: the circle through the pointer around the bubble's centre, snapped
    /// to the nearest size and shrunk to one that fits `region`. `nil` when none fits.
    public static func resizeTarget(pointer: CGPoint, circle: CGRect, region: CGRect, inset: CGFloat) -> CameraBubbleSize? {
        let distance = hypot(pointer.x - circle.midX, pointer.y - circle.midY)
        return CameraBubbleSize.fitting(.nearest(toDiameter: distance * 2), in: region, inset: inset)
    }

    /// Bottom-left corner of `region` (AppKit space, bottom-left origin), so the bubble lands inside the recording.
    public static func initialFrame(in region: CGRect, diameter: CGFloat, inset: CGFloat) -> CGRect {
        CGRect(x: region.minX + inset, y: region.minY + inset, width: diameter, height: diameter)
    }

    /// Keeps a resized bubble's center where it was.
    public static func resized(_ frame: CGRect, to diameter: CGFloat) -> CGRect {
        CGRect(x: frame.midX - diameter / 2, y: frame.midY - diameter / 2, width: diameter, height: diameter)
    }

    /// Moves `frame` the least distance that keeps it inside `region` with `inset` on each side,
    /// favouring the bottom-left when it can't fit.
    public static func clamped(_ frame: CGRect, in region: CGRect, inset: CGFloat) -> CGRect {
        let x = max(min(frame.minX, region.maxX - inset - frame.width), region.minX + inset)
        let y = max(min(frame.minY, region.maxY - inset - frame.height), region.minY + inset)
        return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
    }
}
