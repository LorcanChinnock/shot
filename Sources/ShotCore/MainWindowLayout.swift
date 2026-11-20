import Foundation

/// When the one Shot window's sidebar fits (#1460). Below that width it hides behind a toolbar button, as in Finder and
/// Mail, and the library grid drops to fewer columns.
public enum MainWindowLayout {
    /// The narrowest the window goes: the toolbar and two columns of thumbnails, with the sidebar hidden.
    public static let minWidth = 640.0
    /// The room the page beside the sidebar needs, for two columns of settings cards or a few columns of thumbnails.
    public static let minContentWidth = 560.0

    /// Whether a sidebar `sidebarWidth` wide leaves the page enough room in a window `windowWidth` wide.
    public static func sidebarFits(windowWidth: Double, sidebarWidth: Double) -> Bool {
        windowWidth - sidebarWidth >= minContentWidth
    }

    /// Whether the sidebar shows. Where it fits, it follows the sidebar button (`wanted`). Where it doesn't, it's hidden
    /// unless the button brought it back (`revealed`).
    public static func showsSidebar(windowWidth: Double, sidebarWidth: Double, wanted: Bool, revealed: Bool) -> Bool {
        sidebarFits(windowWidth: windowWidth, sidebarWidth: sidebarWidth) ? wanted : revealed
    }
}
