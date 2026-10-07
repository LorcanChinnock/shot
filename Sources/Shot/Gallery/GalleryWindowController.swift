import AppKit
import os
import ShotCore

private let log = Logger.shot("gallery")

private final class GalleryWindow: NSWindow {
    var onCommand: ((String, Bool) -> Bool)?
    var onKey: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), onCommand?(key, flags.contains(.shift)) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Arrows, Return, Space, Delete and Escape work wherever focus is, except while typing in the search field.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class GalleryWindowController: NSObject, NSWindowDelegate {
    static let shared = GalleryWindowController()

    var onEdit: ((URL) -> Void)? {
        get { model.onEdit }
        set { model.onEdit = newValue }
    }

    var onExportGIF: ((URL) -> Void)? {
        get { model.onExportGIF }
        set { model.onExportGIF = newValue }
    }

    private let model = GalleryModel()
    private var window: GalleryWindow?

    func show() {
        if window == nil {
            makeWindow()
        }
        guard let window else {
            return
        }
        model.start()
        GlassWindow.present(window)
        // Keeps the search field from taking focus, so the arrow keys move through the grid.
        window.makeFirstResponder(nil)
        log.notice("Gallery opened")
    }

    private func makeWindow() {
        let visible = (NSScreen.underPointer ?? NSScreen.screens[0]).visibleFrame
        let size = CGSize(width: min(1080, visible.width * 0.85), height: min(720, visible.height * 0.85))
        let window = GalleryWindow()
        GlassWindow.make(window, size: size, title: "Shot Gallery", resizable: true) {
            GalleryRootView(model: model)
        }
        window.delegate = self
        window.minSize = NSSize(width: 860, height: 420)
        window.onCommand = { [weak self] key, shift in
            self?.handleCommand(key, shift: shift, in: window) ?? false
        }
        window.onKey = { [weak self] event in
            self?.handleKey(event, in: window) ?? false
        }
        self.window = window
    }

    private func isTyping(in window: NSWindow) -> Bool {
        window.firstResponder is NSText
    }

    private func handleCommand(_ key: String, shift: Bool, in window: NSWindow) -> Bool {
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

    private func handleKey(_ event: NSEvent, in window: NSWindow) -> Bool {
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

    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
    }
}
