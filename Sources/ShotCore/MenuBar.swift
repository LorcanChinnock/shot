import CoreGraphics
import Foundation

/// The strip along the top of a screen. All rects are in AppKit space.
public enum MenuBar {
    /// The menu bar's height, or the notch's when the menu bar hides; 0 on a screen with neither.
    public static func height(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat) -> CGFloat {
        max(screenFrame.maxY - visibleFrame.maxY, safeAreaTop)
    }

    /// `screenFrame` without the strip `height` measures.
    public static func frameBelow(screenFrame: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: screenFrame.height - height)
    }
}
