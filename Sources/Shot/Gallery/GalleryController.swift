import AppKit
import os
import ShotCore

private let log = Logger.shot("gallery")

/// The gallery section's model and keyboard handling inside the main window.
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
        MainWindowController.show(section: .gallery)
        log.notice("Gallery opened")
    }

    private func isTyping(in window: NSWindow) -> Bool {
        window.firstResponder is NSText
    }

    func handleCommand(_ key: String, shift: Bool, in window: NSWindow) -> Bool {
        switch key {
        case "w":
            window.performClose(nil)
        case "f":
            model.searchFocusRequest += 1
        case "=", "+":
            model.zoom(by: 30)
        case "-":
            model.zoom(by: -30)
        case "a" where !isTyping(in: window):
            model.selectAll()
        case "c" where !isTyping(in: window) && !model.selection.isEmpty:
            model.copy(model.selectedItems)
        case "z" where !isTyping(in: window) && !shift && model.canUndoTrash:
            model.undoTrash()
        case "\u{7f}" where !isTyping(in: window):
            model.trash(model.selectedItems)
        default:
            return false
        }
        return true
    }

    /// Arrows, Return, Space, Delete and Escape work wherever focus is, except while typing in the search field.
    func handleKey(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return false
        }
        if isTyping(in: window) {
            guard event.keyCode == 53 else {
                return false
            }
            window.makeFirstResponder(nil)
            return true
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
            model.edit(model.selectedItems)
        case 49: // Space
            GalleryPreview.shared.toggle(model.selectedItems.map(\.url))
        case 51, 117: // Delete, Forward Delete
            guard !model.selection.isEmpty else {
                return false
            }
            model.trash(model.selectedItems)
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
}
