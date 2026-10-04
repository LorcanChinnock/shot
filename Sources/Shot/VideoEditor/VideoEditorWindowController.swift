import AppKit
import os
import ShotCore

private let log = Logger.shot("video-editor")

private final class VideoEditorWindow: NSWindow {
    var onCommand: ((String, Bool) -> Bool)?
    var onKey: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), onCommand?(key, flags.contains(.shift)) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Space and the arrow keys drive the player wherever focus is; the window has no text fields.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class VideoEditorWindowController: NSObject, NSWindowDelegate {
    private static var open: [VideoEditorWindowController] = []

    private let model: VideoEditorModel
    private let window: NSWindow

    static func open(_ url: URL) {
        if let existing = open.first(where: { $0.model.fileURL == url }) {
            GlassWindow.present(existing.window)
            return
        }
        Task {
            let model = VideoEditorModel(fileURL: url)
            guard await model.load() else {
                model.teardown()
                Toast.show("Cannot open \(url.lastPathComponent)")
                return
            }
            // A second request for the same file may have finished loading first.
            if let existing = open.first(where: { $0.model.fileURL == url }) {
                model.teardown()
                GlassWindow.present(existing.window)
                return
            }
            let controller = VideoEditorWindowController(model: model)
            open.append(controller)
            GlassWindow.present(controller.window)
            log.notice("Video editor opened: \(url.path)")
        }
    }

    private init(model: VideoEditorModel) {
        self.model = model
        let visible = (NSScreen.underPointer ?? NSScreen.screens[0]).visibleFrame
        let width = min(max(860, visible.width * 0.6), visible.width * 0.85)
        let playerHeight = min((width - Brutal.windowInset * 2) / model.aspectRatio, visible.height * 0.55)
        let size = CGSize(width: width, height: playerHeight + VideoEditorRootView.chromeHeight)
        let editorWindow = VideoEditorWindow()
        window = editorWindow
        super.init()

        GlassWindow.make(editorWindow, size: size, title: model.fileURL.lastPathComponent, resizable: true) {
            VideoEditorRootView(model: model)
        }
        window.delegate = self
        // Wide enough for the export options in one row.
        window.minSize = NSSize(width: 800, height: 200 + VideoEditorRootView.chromeHeight)

        editorWindow.onCommand = { [weak self] key, shift in
            self?.handleCommand(key, shift: shift) ?? false
        }
        editorWindow.onKey = { [weak self] event in
            self?.handleKey(event) ?? false
        }
    }

    private func handleCommand(_ key: String, shift: Bool) -> Bool {
        switch key {
        case "z":
            shift ? model.redo() : model.undo()
        case "c":
            Task { await model.copy() }
        case "s":
            Task { await model.save() }
        case "w":
            window.performClose(nil)
        default:
            return false
        }
        return true
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
            return false
        }
        switch event.keyCode {
        case 49: // Space
            model.togglePlay()
        case 123: // Left arrow
            model.step(-1)
        case 124: // Right arrow
            model.step(1)
        default:
            return false
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty, !model.isExporting else {
            return !model.isExporting
        }
        let alert = NSAlert()
        alert.messageText = "Save the trimmed \(model.fileURL.lastPathComponent)?"
        alert.informativeText = "Your trim is lost if you discard it."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Exporting takes a moment, so close once the file is written.
            Task {
                if await model.save() {
                    window.close()
                }
            }
            return false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.teardown()
        Self.open.removeAll { $0 === self }
    }
}
