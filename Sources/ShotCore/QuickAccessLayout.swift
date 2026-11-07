import CoreGraphics
import Foundation

/// Where Quick Access cards sit in their panel: stacked upward from the bottom, the last card lowest, with `padding`
/// round them and `spacing` between. Frames are in the panel's bottom-left-origin coordinates, as AppKit has them.
/// The panel's SwiftUI view lays the cards out the same way, and the hover check finds a card by its frame here.
public struct QuickAccessLayout: Equatable, Sendable {
    public static let cardWidth: CGFloat = 280
    /// The shortest and tallest a card gets. The capture fills the card, so a picture taller or wider than these allow
    /// is cropped to the middle rather than letterboxed.
    public static let cardMinHeight: CGFloat = 158
    public static let cardMaxHeight: CGFloat = 210
    public static let spacing: CGFloat = 14
    public static let padding: CGFloat = 10

    public let size: CGSize
    /// One frame per card height, in the same order.
    public let cardFrames: [CGRect]

    /// The height of a card for a picture `size` big: the picture's shape at the card's width, within the limits.
    public static func cardHeight(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else {
            return cardMaxHeight
        }
        return min(cardMaxHeight, max(cardMinHeight, (cardWidth * size.height / size.width).rounded()))
    }

    public init(cardHeights heights: [CGFloat]) {
        var frames: [CGRect] = []
        var y = Self.padding
        for height in heights.reversed() {
            frames.append(CGRect(x: Self.padding, y: y, width: Self.cardWidth, height: height))
            y += height + Self.spacing
        }
        cardFrames = frames.reversed()
        let cardsHeight = heights.reduce(0, +) + Self.spacing * CGFloat(max(0, heights.count - 1))
        size = CGSize(width: Self.cardWidth + Self.padding * 2, height: cardsHeight + Self.padding * 2)
    }
}
