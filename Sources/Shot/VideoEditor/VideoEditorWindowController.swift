import AppKit
import os
import ShotCore

private let log = Logger.shot("video-editor")

private final class VideoEditorWindow: NSWindow {
    var onCommand: ((String, Bool) -> Bool)?
    var onKey: ((NSEvent) -> Bool)?

    /// An annotation's text field is being edited, which keeps its keys, including the shortcuts.
    private var isEditingText: Bool { firstResponder is NSText }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isEditingText else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), onCommand?(key, flags.contains(.shift)) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Space, the arrow keys, Delete and Escape work wherever focus is, except in a text field.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !isEditingText, onKey?(event) == true {
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
    /// How much of the window's height is the tracks panel.
    private var appliedExtraHeight: CGFloat = 0
    private var discarding = false

    static func open(_ url: URL) {
        if let existing = open.first(where: { $0.model.fileURL == url }) {
            GlassWindow.present(existing.window)
            return
        }
        Task {
            let model = VideoEditorModel(fileURL: url)
            do {
                try await model.load()
            } catch {
                model.teardown()
                Toast.error("Cannot open \(url.lastPathComponent): \(error.localizedDescription)")
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
        let width = min(max(880, visible.width * 0.6), visible.width * 0.85)
        let playerHeight = min((width - Brutal.windowInset * 2) / model.aspectRatio, visible.height * 0.55)
        let size = CGSize(width: width, height: playerHeight + VideoEditorRootView.chromeHeight)
        let editorWindow = VideoEditorWindow()
        window = editorWindow
        super.init()

        GlassWindow.make(editorWindow, size: size, title: model.fileURL.lastPathComponent, resizable: true) {
            VideoEditorRootView(model: model)
        }
        window.delegate = self
        // Wide enough for the export options in one row, GIF's included.
        window.minSize = NSSize(width: 880, height: VideoEditorRootView.playerFloor + VideoEditorRootView.chromeHeight)

        model.onLayoutChanged = { [weak self] in
            self?.fitWindowToTracks()
        }
        fitWindowToTracks(animate: false)
        editorWindow.onCommand = { [weak self] key, shift in
            self?.handleCommand(key, shift: shift) ?? false
        }
        editorWindow.onKey = { [weak self] event in
            self?.handleKey(event) ?? false
        }
    }

    /// Grows or shrinks the window as the panel does, keeping its top edge where it is.
    private func fitWindowToTracks(animate: Bool = true) {
        let extra = model.tracksExtraHeight
        guard extra != appliedExtraHeight else {
            return
        }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        // On a short screen the tracks scroll instead, so the minimum never asks for more than the screen has.
        window.minSize.height = min(VideoEditorRootView.playerFloor + VideoEditorRootView.chromeHeight + extra, visible.height)
        var frame = window.frame
        // The preview gives way before the window runs off the screen.
        let height = min(max(window.minSize.height, frame.height + extra - appliedExtraHeight), visible.height)
        frame.origin.y += frame.height - height
        frame.size.height = height
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - height)
        appliedExtraHeight = extra
        window.setFrame(frame, display: true, animate: animate)
    }

    private func handleCommand(_ key: String, shift: Bool) -> Bool {
        switch key {
        case "z":
            shift ? model.redo() : model.undo()
        case "c":
            Task { await model.copy() }
        case "s":
            Task { await model.save() }
        case "=", "+":
            model.zoom(bySteps: 1)
        case "-":
            model.zoom(bySteps: -1)
        case "0":
            model.resetZoom()
        case "w":
            window.performClose(nil)
        default:
            return false
        }
        return true
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return false
        }
        // Shift jumps a second instead of a frame.
        if event.modifierFlags.contains(.shift) {
            switch event.keyCode {
            case 123: model.seek(to: max(model.range.start, model.currentTime - 1))
            case 124: model.seek(to: min(model.range.end, model.currentTime + 1))
            default: return false
            }
            return true
        }
        switch event.keyCode {
        case 115: // Home
            model.seek(to: model.range.start)
        case 119: // End
            model.seek(to: model.range.end)
        case 49: // Space
            model.togglePlay()
        case 123: // Left arrow
            model.step(-1)
        case 124: // Right arrow
            model.step(1)
        case 51, 117: // Delete, Forward Delete
            return model.deleteSelectedKeyframe() || model.cutSelection() || model.deleteSelectedClip()
        case 1: // S
            return model.split()
        case 40: // K
            model.toggleAllKeyframes()
        case 17: // T
            model.toggleTracks()
        case 45: // N
            model.toggleSnapping()
        case 53: // Escape
            return model.clearSelection() || model.escapeAnnotating()
        default:
            return false
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty, !model.isExporting, !discarding else {
            return !model.isExporting
        }
        guard sender.attachedSheet == nil else {
            return false
        }
        let alert = NSAlert()
        alert.messageText = model.isComposite ? "Save a copy of the edited \(model.fileURL.lastPathComponent)?" : "Save the edited \(model.fileURL.lastPathComponent)?"
        alert.informativeText = "Your edits are lost if you discard them."
        alert.addButton(withTitle: model.isComposite ? "Save Copy" : "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: sender) { [self] response in
            switch response {
            case .alertFirstButtonReturn:
                // Exporting takes a moment, so close once the file is written.
                Task {
                    if await model.save() {
                        sender.close()
                    }
                }
            case .alertSecondButtonReturn:
                discarding = true
                sender.close()
            default:
                break
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        model.teardown()
        Self.open.removeAll { $0 === self }
    }
}
