import CoreGraphics
import Foundation

/// Where the capture overlay puts its bar, so it stays off what is being picked and 16 pt clear of the Dock or the screen's edge.
/// Rects are in one screen's view space, with y going up, as AppKit draws it. `visible` is the part of the screen the Dock and
/// menu bar leave, as `NSScreen.visibleFrame` gives it.
public enum OverlayBarPlacement: Sendable, Equatable {
    case bottom
    case top
    case hidden

    /// What the person is picking, which the bar keeps clear of.
    public enum Aim: Sendable, Equatable {
        /// An area made with the arrow keys: its edges matter, so any overlap moves the bar.
        case area(CGRect)
        /// A highlighted window or page: a click anywhere on it picks it, so the bar moves only when it would cover a good part of it.
        case target(CGRect)
    }

    /// From the Dock, the menu bar, or the screen's edge where they hide, to the near side of the bar.
    static let inset: CGFloat = 16
    /// Extra room kept around the bar, which also covers its offset shadow.
    static let clearance: CGFloat = 8
    /// The share of a window or page the bar may cover before it moves.
    static let coveredShare: CGFloat = 0.25

    /// The frame of a bar of `size`, centred across the visible area at this edge; nil when hidden.
    public func frame(of size: CGSize, visible: CGRect) -> CGRect? {
        let x = (visible.midX - size.width / 2).rounded()
        switch self {
        case .bottom:
            return CGRect(x: x, y: visible.minY + Self.inset, width: size.width, height: size.height)
        case .top:
            return CGRect(x: x, y: visible.maxY - Self.inset - size.height, width: size.width, height: size.height)
        case .hidden:
            return nil
        }
    }

    /// Hidden while an area is dragged out. Otherwise at the bottom above the Dock, as the macOS screenshot bar is, unless the aim is under it, then
    /// at the top, else hidden. While the pointer is on the bar, it stays where it is, so a button never moves out from under a click.
    public static func placement(for size: CGSize, visible: CGRect, avoiding aim: Aim?, dragging: Bool, current: Self, pointerOnBar: Bool) -> Self {
        if dragging {
            return .hidden
        }
        if pointerOnBar, current != .hidden {
            return current
        }
        guard let aim else {
            return .bottom
        }
        for edge in [Self.bottom, .top] {
            if let frame = edge.frame(of: size, visible: visible), !blocks(frame.insetBy(dx: -clearance, dy: -clearance), aim) {
                return edge
            }
        }
        return .hidden
    }

    private static func blocks(_ frame: CGRect, _ aim: Aim) -> Bool {
        switch aim {
        case let .area(rect):
            return frame.intersects(rect)
        case let .target(rect):
            let overlap = frame.intersection(rect)
            guard !overlap.isNull, rect.width > 0, rect.height > 0 else {
                return false
            }
            return overlap.width * overlap.height > rect.width * rect.height * coveredShare
        }
    }
}
