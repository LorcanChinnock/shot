import Foundation

/// What happens once a screenshot or recording is taken, from the after-capture settings: whether it's copied, whether
/// it's written to a file, and what shows next. Screenshots and recordings decide it here so they stay alike.
public struct AfterCapture: Equatable, Sendable {
    public enum Next: Equatable, Sendable {
        case editor
        case quickAccess
        /// A toast saying what was done, when nothing else shows it.
        case toast(String)
        case nothing
    }

    public var copies: Bool
    /// True when a screenshot has to be written to a file: to keep, or for Quick Access or the editor to open. A
    /// recording is in its file from the start.
    public var writesFile: Bool
    public var next: Next

    public init(copies: Bool, writesFile: Bool, next: Next) {
        self.copies = copies
        self.writesFile = writesFile
        self.next = next
    }

    public static func plan(prefs: Preferences, isVideo: Bool) -> AfterCapture {
        plan(
            copy: isVideo ? prefs.copyAfterRecording : prefs.copyAfterCapture, save: prefs.saveAfterCapture,
            quickAccess: prefs.quickAccessAfterCapture, openEditor: prefs.openEditorAfterCapture, isVideo: isVideo
        )
    }

    /// A recording never opens the editor by itself (#209): it shows its Quick Access card instead.
    static func plan(copy: Bool, save: Bool, quickAccess: Bool, openEditor: Bool, isVideo: Bool) -> AfterCapture {
        let next: Next = if openEditor, !isVideo {
            .editor
        } else if quickAccess {
            .quickAccess
        } else if copy {
            .toast("Copied to clipboard")
        } else if save {
            .toast("Saved")
        } else {
            .nothing
        }
        return AfterCapture(copies: copy, writesFile: !isVideo && (save || quickAccess || openEditor), next: next)
    }
}
