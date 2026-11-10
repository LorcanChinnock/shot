import AppKit
import os
import ShotCore

private let log = Logger.shot("gallery")

/// The gallery's model and its keyboard handling in the gallery window.
@MainActor
final class GalleryController {
    static let shared = GalleryController()

    var onEdit: ((URL) -> Void)? {
        get { model.onEdit }
        set { model.onEdit = newValue }
    }

    var onExportGIF: ((URL) -> Void)? {
        get { model.onExportGIF }
        set { model.onExportGIF = newValue }
    }

    let model = GalleryModel()

    func show() {
        GalleryWindowController.show()
        log.notice("Gallery opened")
    }

    private func isTyping(in window: NSWindow) -> Bool {
        window.firstResponder is NSText
    }

    func handleCommand(_ key: String, shift: Bool, in window: NSWindow) -> Bool {
        // The Move to Trash dialog has the keyboard while it's open.
        guard model.trashRequest == nil else {
            return false
        }
        // Thumbnail size and Select All act on the grid, which the preview covers.
        if model.previewing != nil, ["=", "+", "-", "a"].contains(key) {
            return true
        }
        switch key {
        case "w":
            window.performClose(nil)
        case "f":
            // The search field is in the grid's toolbar, so searching goes back to the grid.
            model.closePreview()
            model.searchFocusRequest += 1
        case "=", "+":
            model.zoom(by: 30)
        case "-":
            model.zoom(by: -30)
        case "a" where !isTyping(in: window):
            if shift {
                model.clearSelection()
            } else {
                model.selectAll()
            }
        case "c" where !isTyping(in: window) && !model.selection.isEmpty:
            model.copy(model.selectedItems)
        case "r" where !isTyping(in: window) && !model.selection.isEmpty:
            model.reveal(model.selectedItems)
        case "z" where !isTyping(in: window) && !shift && model.canUndoTrash:
            model.undoTrash()
        case "\u{7f}" where !isTyping(in: window):
            // ⌘⌫ trashes without asking, as in Photos and Finder. ⌘Z still puts it back.
            model.trash(model.selectedItems)
        default:
            return false
        }
        return true
    }

    /// Arrows, Return, Space, Delete and Escape work wherever focus is, except while typing in the search field.
    func handleKey(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty, model.trashRequest == nil else {
            return false
        }
        if isTyping(in: window) {
            guard event.keyCode == 53 else {
                return false
            }
            window.makeFirstResponder(nil)
            model.searchBlurRequest += 1
            return true
        }
        // After the typing check, so Return in the preview's Tag popover adds the tag rather than opening the editor.
        if model.previewing != nil {
            return handlePreviewKey(event, in: window)
        }
        let extending = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123: model.move(.left, extending: extending)
        case 124: model.move(.right, extending: extending)
        case 125: model.move(.down, extending: extending)
        case 126: model.move(.up, extending: extending)
        case 115: model.move(.first, extending: extending)
        case 119: model.move(.last, extending: extending)
        case 36, 76: // Return, Enter
            guard !model.selection.isEmpty else {
                return false
            }
            model.edit(model.selectedItems)
        case 49: // Space
            guard !model.selection.isEmpty else {
                return false
            }
            model.previewSelection()
        case 51, 117: // Delete, Forward Delete
            guard !model.selection.isEmpty else {
                return false
            }
            model.askToTrash(model.selectedItems)
        case 53: // Escape
            guard !model.selection.isEmpty else {
                return false
            }
            model.clearSelection()
        default:
            return false
        }
        return true
    }

    /// In the preview, ← and → step through the captures in the grid's order, and Space and Escape go back to the grid.
    /// The previewed capture is the selection, so Return and Delete act on it as they do in the grid.
    private func handlePreviewKey(_ event: NSEvent, in window: NSWindow) -> Bool {
        switch event.keyCode {
        case 123, 126: model.stepPreview(by: -1) // Left, Up
        case 124, 125: model.stepPreview(by: 1) // Right, Down
        case 115: model.previewEnd(last: false) // Home
        case 119: model.previewEnd(last: true) // End
        case 49, 53: model.closePreview() // Space, Escape
        case 36, 76: model.edit(model.selectedItems) // Return, Enter
        case 51, 117: model.askToTrash(model.selectedItems) // Delete, Forward Delete
        default: return false
        }
        return true
    }
}
