import CoreGraphics
import Foundation

/// A Dock set to hide itself, which macOS leaves out of `NSScreen.visibleFrame` even while it's showing.
public enum AutoHideDock {
    /// From the screen's bottom edge to the top of a showing Dock, beyond its icons: measured as 25 pt with 54 pt icons
    /// on macOS 26.
    static let padding: CGFloat = 25
    /// The Dock's own default icon size, for when `tilesize` was never set.
    static let defaultTileSize: CGFloat = 64

    /// How far a showing Dock at the bottom reaches up the screen, from its `com.apple.dock` settings; nil when it doesn't
    /// hide itself or sits on a side.
    public static func height(autohide: Bool, orientation: String?, tileSize: CGFloat?) -> CGFloat? {
        guard autohide, orientation == nil || orientation == "bottom" else {
            return nil
        }
        return (tileSize ?? defaultTileSize) + padding
    }

    /// `visible` with a showing Dock of `height` taken off its bottom, for the screen that holds the Dock.
    public static func visible(_ visible: CGRect, in bounds: CGRect, shownHeight height: CGFloat?) -> CGRect {
        guard let height, visible.minY < bounds.minY + height else {
            return visible
        }
        let bottom = bounds.minY + height
        return CGRect(x: visible.minX, y: bottom, width: visible.width, height: visible.maxY - bottom)
    }
}
