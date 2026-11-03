import CoreGraphics
import Foundation

/// Where the capture overlay puts its hint and chips, so they stay off what is being picked.
/// Rects are in one screen's view space, with y going up, as AppKit draws it.
public enum OverlayBarPlacement: Sendable, Equatable {
    case top
    case bottom
    case hidden

    /// What the person is picking, which the hint and chips keep clear of.
    public enum Aim: Sendable, Equatable {
        /// An area being dragged out or made with the arrow keys: its edges matter, so any overlap moves the chips.
        case area(CGRect)
        /// A highlighted window or page: a click anywhere on it picks it, so the chips move only when they would cover a good part of it.
        case target(CGRect)
    }

    /// From the screen's edge to the near side of the block, top or bottom.
    public static let edgeInset: CGFloat = 64
    /// Between the hint and the row of chips under it.
    public static let rowGap: CGFloat = 22
    /// Extra room kept around the block, which also covers its chips' offset shadows.
    static let clearance: CGFloat = 8
    /// The share of a window or page the block may cover before it moves.
    static let coveredShare: CGFloat = 0.25

    /// The frame of a block of `size`, centred across the screen at this edge; nil when hidden.
    public func frame(of size: CGSize, in bounds: CGRect) -> CGRect? {
        let x = (bounds.midX - size.width / 2).rounded()
        switch self {
        case .top:
            return CGRect(x: x, y: bounds.maxY - Self.edgeInset - size.height, width: size.width, height: size.height)
        case .bottom:
            return CGRect(x: x, y: bounds.minY + Self.edgeInset, width: size.width, height: size.height)
        case .hidden:
            return nil
        }
    }

    /// Top unless the aim is under it, then the bottom, else hidden. While the pointer is on a chip, the block stays where it is,
    /// so a chip never moves out from under a click.
    public static func placement(for size: CGSize, in bounds: CGRect, avoiding aim: Aim?, current: Self, pointerOnChip: Bool) -> Self {
        if pointerOnChip, current != .hidden {
            return current
        }
        guard let aim else {
            return .top
        }
        for edge in [Self.top, .bottom] {
            if let frame = edge.frame(of: size, in: bounds), !blocks(frame.insetBy(dx: -clearance, dy: -clearance), aim) {
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
