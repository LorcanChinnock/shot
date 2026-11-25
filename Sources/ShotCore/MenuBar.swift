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

    /// Shot's icon shows when the setting asks for it, and also, while hidden, when it has something live to say: the
    /// countdown's seconds, the recording's time, or the dot of an update waiting to be opened.
    public static func showsIcon(setting: Bool, isCountingDown: Bool, isRecording: Bool, updatePending: Bool) -> Bool {
        setting || isCountingDown || isRecording || updatePending
    }
}
