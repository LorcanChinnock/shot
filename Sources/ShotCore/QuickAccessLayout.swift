import CoreGraphics
import Foundation

/// Where Quick Access cards sit in their panel. At rest they're a stack: the newest card in front at the bottom, and the
/// older ones behind it, smaller, with their top edge showing `peek` above it. Fanned out, when the pointer is on the
/// stack, every card shows in full, stacked upward with `spacing` between and the newest lowest. The newest card is in
/// the same place either way. Frames are in the panel's bottom-left-origin coordinates, as AppKit has them, with
/// `padding` round the cards. The panel's SwiftUI view places the cards from here, and the hover check finds a card by its
/// frame here.
public struct QuickAccessLayout: Equatable, Sendable {
    public static let cardWidth: CGFloat = 280
    /// The shortest and tallest a card gets. The capture fills the card, so a picture taller or wider than these allow
    /// is cropped to the middle rather than letterboxed.
    public static let cardMinHeight: CGFloat = 158
    public static let cardMaxHeight: CGFloat = 210
    public static let spacing: CGFloat = 14
    public static let padding: CGFloat = 10
    /// How far the panel sits in from the side and bottom of the screen's visible frame, so a card's outer edge is
    /// `screenInset + padding` in.
    public static let screenInset: CGFloat = 20
    /// How far the cards behind the front one show above it at rest.
    public static let peek: CGFloat = 14
    /// The size of a card behind the front one at rest, shrunk towards its bottom middle.
    public static let behindScale: CGFloat = 0.94

    /// Where one card goes.
    public struct Placement: Equatable, Sendable {
        /// The card's height before `scale`. A card behind the front one takes the front card's height, so no part of it
        /// shows below the front card.
        public let height: CGFloat
        /// 1, or `behindScale` for a card behind the front one.
        public let scale: CGFloat
        /// Where the card is drawn, after `scale`, to the nearest point.
        public let frame: CGRect

        public var isBehind: Bool { scale < 1 }
    }

    public let size: CGSize
    /// One placement per card height, in the same order.
    public let placements: [Placement]

    public var cardFrames: [CGRect] { placements.map(\.frame) }

    /// The height of a card for a picture `size` big: the picture's shape at the card's width, within the limits.
    public static func cardHeight(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else {
            return cardMaxHeight
        }
        return min(cardMaxHeight, max(cardMinHeight, (cardWidth * size.height / size.width).rounded()))
    }

    /// `heights` runs oldest first, so the last card is the newest and in front.
    public init(cardHeights heights: [CGFloat], fannedOut: Bool) {
        let width = Self.cardWidth + Self.padding * 2
        guard let front = heights.last else {
            placements = []
            size = CGSize(width: width, height: Self.padding * 2)
            return
        }
        if fannedOut {
            var placements: [Placement] = []
            var y = Self.padding
            for height in heights.reversed() {
                placements.append(Placement(height: height, scale: 1, frame: CGRect(x: Self.padding, y: y, width: Self.cardWidth, height: height)))
                y += height + Self.spacing
            }
            self.placements = placements.reversed()
            size = CGSize(width: width, height: y - Self.spacing + Self.padding)
            return
        }
        let frontPlacement = Placement(height: front, scale: 1, frame: CGRect(x: Self.padding, y: Self.padding, width: Self.cardWidth, height: front))
        let behindWidth = (Self.cardWidth * Self.behindScale).rounded()
        let behindHeight = (front * Self.behindScale).rounded()
        let top = Self.padding + front + Self.peek
        let behind = Placement(
            height: front,
            scale: Self.behindScale,
            frame: CGRect(x: Self.padding + ((Self.cardWidth - behindWidth) / 2).rounded(), y: top - behindHeight, width: behindWidth, height: behindHeight)
        )
        placements = Array(repeating: behind, count: heights.count - 1) + [frontPlacement]
        size = CGSize(width: width, height: front + (heights.count > 1 ? Self.peek : 0) + Self.padding * 2)
    }

    /// The index of the card drawn at `point`, the frontmost where cards overlap; `nil` between or outside them.
    public func card(at point: CGPoint) -> Int? {
        // Later cards are drawn over earlier ones.
        placements.indices.reversed().first { placements[$0].frame.contains(point) }
    }
}
