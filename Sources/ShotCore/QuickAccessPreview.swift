import CoreGraphics
import Foundation

/// Where things go in Settings › Quick Access's preview: a desktop as wide as the pane, with a Quick Access card in the
/// chosen corner, placed as the real panel places it and scaled to the preview. Points are the preview's own, with y going
/// down, as SwiftUI lays it out.
public struct QuickAccessPreviewLayout: Equatable, Sendable {
    /// The width of the display the preview pictures, in points, so a 720 pt preview draws it at half size.
    public static let screenWidth: CGFloat = 1440
    public static let menuBarHeight: CGFloat = 24
    /// The sample capture on the card, 16:10, which gives a card 175 pt tall.
    public static let captureSize = CGSize(width: 1600, height: 1000)
    /// The sample window in the middle of the desktop, in the pictured display's points: Settings › Capture's 270 × 170 pt
    /// sample window at 2.8 times the size.
    public static let windowSize = CGSize(width: 756, height: 476)
    /// From the menu bar to the sample window's top, in the pictured display's points.
    public static let windowTop: CGFloat = 70
    /// The least room kept under the sample window, in the preview's points.
    public static let windowMargin: CGFloat = 12
    /// The real card's corner radius, the app's panel radius.
    public static let realCardRadius: CGFloat = 14
    /// The preview is half as tall as it is wide, within these limits, so it never crowds the pane.
    public static let heights: ClosedRange<CGFloat> = 200...340

    public let size: CGSize
    /// Preview points per point of the pictured display.
    public let scale: CGFloat
    public let menuBar: CGRect
    public let window: CGRect
    /// The card where it rests.
    public let card: CGRect
    public let cardRadius: CGFloat
    /// How far the card moves sideways to leave the desktop past its corner's edge: negative to the left.
    public let slide: CGFloat

    /// The preview's height for a pane `width` wide.
    public static func height(forWidth width: CGFloat) -> CGFloat {
        min(max((width / 2).rounded(), heights.lowerBound), heights.upperBound)
    }

    /// The desktop's bottom edge is the display's, so when the preview is shorter than the display's shape the top is
    /// what's cut off, never the corner the card sits in.
    public init(size: CGSize, position: QuickAccessPosition) {
        let scale = max(size.width, 0) / Self.screenWidth
        self.size = size
        self.scale = scale
        menuBar = CGRect(x: 0, y: 0, width: size.width, height: Self.menuBarHeight * scale)

        let windowTop = (Self.menuBarHeight + Self.windowTop) * scale
        // In a short preview the window shrinks, keeping its shape, to leave the margin under it.
        let room = max(size.height - windowTop - Self.windowMargin, 0)
        let windowScale = min(scale, room / Self.windowSize.height)
        let windowWidth = Self.windowSize.width * windowScale
        let windowHeight = Self.windowSize.height * windowScale
        window = CGRect(x: (size.width - windowWidth) / 2, y: windowTop, width: windowWidth, height: windowHeight)

        // The real panel: one card, with the panel's padding round it, set in from the visible frame's corner.
        let panel = QuickAccessLayout(cardHeights: [QuickAccessLayout.cardHeight(for: Self.captureSize)], fannedOut: false)
        let frame = panel.cardFrames[0]
        let inset = QuickAccessLayout.screenInset
        let panelX = position == .left ? inset : Self.screenWidth - inset - panel.size.width
        card = CGRect(
            x: (panelX + frame.minX) * scale,
            y: size.height - (inset + frame.maxY) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
        cardRadius = Self.realCardRadius * scale
        let away = (panel.size.width + inset) * scale
        slide = position == .left ? -away : away
    }

    /// The whole seconds left on the auto-close timer `elapsed` seconds into `duration`, as the caption counts them: the
    /// full duration at the start, and 1 until the last second ends.
    public static func secondsLeft(duration: Double, elapsed: Double) -> Int {
        guard duration > 0 else {
            return 0
        }
        return Int(max(duration - max(elapsed, 0), 0).rounded(.up))
    }
}
