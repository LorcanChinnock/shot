import AppKit
import os
import ShotCore

private let log = Logger.shot("video-editor")

private final class VideoEditorWindow: NSWindow {
    var onCommand: ((String, Bool, Bool) -> Bool)?
    var onKey: ((NSEvent) -> Bool)?
    var undoing: EditorUndo?

    /// An annotation's text field is being edited, which keeps its keys, including the shortcuts other than ⌘Z.
    private var isEditingText: Bool { firstResponder is NSText }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘Z is taken here, before the Edit menu, which would leave it to a text field with nothing left to undo.
        let command = EditorUndo.command(in: event)
        if command.isUndo, let undoing {
            undoing.perform(redo: command.redo, in: self)
            return true
        }
        if RunsTextField.finishTyping(on: event, in: self) {
            return true
        }
        guard !isEditingText else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), onCommand?(key, flags.contains(.shift), flags.contains(.option)) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // Edit › Undo and Redo reach the window when no text view takes them first. NSWindow's own pass them to its undo
    // manager, which only holds a text field's typing, so they'd be greyed out whenever nothing is typed.

    @objc func undo(_ sender: Any?) {
        undoing?.perform(redo: false, in: self)
    }

    @objc func redo(_ sender: Any?) {
        undoing?.perform(redo: true, in: self)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let undoing, item.action == #selector(undo(_:)) || item.action == #selector(redo(_:)) {
            return undoing.route(redo: item.action == #selector(redo(_:)), in: self).isEnabled
        }
        return super.validateUserInterfaceItem(item)
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
final class VideoEditorWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    private static var open: [VideoEditorWindowController] = []
    static var isAnyOpen: Bool { !open.isEmpty }
    static var hasUnsavedChanges: Bool { open.contains { $0.model.hasUnsavedChanges } }

    private let model: VideoEditorModel
    /// The file this window was opened on: a video or GIF opened with its project, or the video itself.
    private let opened: URL
    /// Run once the window has closed, so Flatten opens the file after any Save or Discard sheet.
    private var afterClose: (() -> Void)?
    private let window: NSWindow
    /// How much of the window's height is the lanes past a plain recording's.
    private var appliedExtraHeight: CGFloat = 0
    private var discarding = false
    /// Set while a quit waits on this window's Save / Discard / Cancel sheet; answers true once the window may go.
    private var quitReply: ((Bool) -> Void)?

    /// Asks about each window with unsaved changes in turn, bringing it forward. False if the user cancelled.
    static func confirmQuit() async -> Bool {
        for controller in open where controller.model.hasUnsavedChanges {
            guard await controller.askBeforeQuit() else {
                return false
            }
        }
        return true
    }

    private func askBeforeQuit() async -> Bool {
        GlassWindow.present(window)
        return await withCheckedContinuation { continuation in
            quitReply = { continuation.resume(returning: $0) }
            if windowShouldClose(window) {
                resolveQuit(true)
            }
        }
    }

    private func resolveQuit(_ proceed: Bool) {
        let reply = quitReply
        quitReply = nil
        reply?(proceed)
    }

    /// A video or GIF saved from the editor with its project opens as its recording with that project live, so the
    /// edit can be changed. `flat` opens the file itself, as Flatten does. An import that's gone is left out, with a
    /// toast saying so.
    static func open(_ url: URL, flat: Bool = false) {
        if let existing = existing(url) {
            GlassWindow.present(existing.window)
            return
        }
        let opening = Perf.begin("Window open")
        let saved = flat ? nil : VersionWriter.project(of: url, in: .app)
        let file = saved?.original ?? url
        Task {
            let model = VideoEditorModel(fileURL: file, restoring: saved?.project, version: url)
            do {
                try await model.load()
            } catch {
                model.teardown()
                Toast.error("Can't open \(url.lastPathComponent): \(error.localizedDescription)")
                return
            }
            // A second request for the same file may have finished loading first.
            if let existing = existing(url) {
                model.teardown()
                GlassWindow.present(existing.window)
                return
            }
            let controller = VideoEditorWindowController(model: model, opened: url)
            open.append(controller)
            GlassWindow.present(controller.window)
            Perf.measureWindowOpen("video editor", since: opening)
            if let missing = saved?.missing, !missing.isEmpty {
                Toast.error("Opened without \(missing.map(\.lastPathComponent).formatted(.list(type: .and))), which can't be found")
            }
            log.notice("Video editor opened: \(url.path)\(saved == nil ? "" : " with its project")")
        }
    }

    private static func existing(_ url: URL) -> VideoEditorWindowController? {
        open.first { $0.opened == url || $0.model.version == url }
    }

    private init(model: VideoEditorModel, opened: URL) {
        self.model = model
        self.opened = opened
        let visible = (NSScreen.underPointer ?? NSScreen.screens[0]).visibleFrame
        let width = min(max(880, visible.width * 0.6), visible.width * 0.85)
        let playerHeight = min((width - VideoWell.sideInset * 2) / model.aspectRatio, visible.height * 0.55)
        let size = CGSize(width: width, height: playerHeight + VideoEditorRootView.chromeHeight)
        let editorWindow = VideoEditorWindow()
        window = editorWindow
        super.init()

        GlassWindow.make(editorWindow, size: size, title: model.fileURL.lastPathComponent, resizable: true) {
            VideoEditorRootView(model: model)
        }
        window.delegate = self
        // Wide enough for the controls row in its compact form beside the open Inspector or Export panel.
        window.minSize = NSSize(width: 880, height: VideoEditorRootView.playerFloor + VideoEditorRootView.chromeHeight)

        model.onLayoutChanged = { [weak self] in
            self?.fitWindowToTracks()
        }
        fitWindowToTracks(animate: false)
        editorWindow.onCommand = { [weak self] key, shift, option in
            self?.handleCommand(key, shift: shift, option: option) ?? false
        }
        editorWindow.onKey = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        editorWindow.undoing = EditorUndo(
            canUndo: { [model] in model.history.canUndo },
            canRedo: { [model] in model.history.canRedo },
            undo: { [model] in model.undo() },
            redo: { [model] in model.redo() },
            finishEditing: { [model, weak editorWindow] in
                model.commitPendingText?()
                editorWindow?.makeFirstResponder(nil)
            }
        )
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
        window.setFrame(frame, display: true, animate: animate && !Motion.reduced)
    }

    private func handleCommand(_ key: String, shift: Bool, option: Bool) -> Bool {
        switch key {
        // ⌥⌘C and ⌥⌘V copy and paste a style, so they're matched before ⌘C.
        case "c" where option:
            model.copyStyle()
        case "v" where option:
            model.pasteStyle()
        case "i" where option:
            model.toggleInspector()
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
        case "]":
            return model.moveSelectedClip(option ? .toFront : .forward)
        case "[":
            return model.moveSelectedClip(option ? .toBack : .backward)
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
        // Crop mode takes Return, Esc and Delete, and leaves the playhead where the picture is.
        if model.isCropping {
            switch event.keyCode {
            case 36, 76: model.applyCrop()
            case 53: model.cancelCrop()
            case 51, 117: model.resetCrop()
            default: return false
            }
            return true
        }
        switch event.keyCode {
        case 8: // C, which keeps the drawing tools showing when it's pressed while drawing
            return model.cropFromDrawTools()
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
        case 45: // N
            model.toggleSnapping()
        case 53: // Escape
            return model.cancelExport() || model.clearSelection() || model.escapeAnnotating() || model.closeExportPanel()
        default:
            return false
        }
        return true
    }

    // The Edit menu's style items, Trim Idle Time and Flatten, which reach the editor through the key window's delegate. Apply Style
    // to All Images is the photo editor's alone.

    @objc func copyStyle(_ sender: Any?) {
        model.copyStyle()
    }

    @objc func resetStyle(_ sender: Any?) {
        model.resetToolOptions()
    }

    @objc func pasteStyle(_ sender: Any?) {
        model.pasteStyle()
    }

    /// Closes the project and opens the file it was saved as by itself: a video here, a GIF in the image editor.
    /// Unsaved changes are asked about first, and a Save Copy makes the new copy the one opened.
    @objc func flatten(_ sender: Any?) {
        afterClose = { [model] in
            guard let version = model.version else {
                return
            }
            switch EditorRoute(fileURL: version) {
            case .video: Self.open(version, flat: true)
            case .image: EditorWindowController.open(version, flat: true)
            }
        }
        window.performClose(nil)
    }

    /// Trims the still start and end of the recording, keeping any speech.
    @objc func trimIdleTime(_ sender: Any?) {
        Task { await model.trimIdleTime() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(trimIdleTime(_:)): model.canTrimIdleTime
        case #selector(copyStyle(_:)): model.targetStyleKind != nil
        case #selector(pasteStyle(_:)): model.canPasteStyle
        case #selector(resetStyle(_:)): model.annotationTool != nil && !model.isCropping && model.canResetToolOptions
        case #selector(flatten(_:)): model.version != nil
        default: true
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.cancelExport() {
            Task {
                await model.exportEnded()
                if windowShouldClose(sender) {
                    sender.close()
                }
            }
            return false
        }
        guard model.hasUnsavedChanges, !discarding else {
            return true
        }
        guard sender.attachedSheet == nil else {
            cancelClose()
            return false
        }
        let alert = NSAlert()
        alert.messageText = model.isComposite ? String(localized: "Save changes to \(model.fileURL.lastPathComponent) as a copy?") : String(localized: "Save changes to \(model.fileURL.lastPathComponent)?")
        alert.informativeText = String(localized: "Your edits are lost if you discard them.")
        alert.addButton(withTitle: model.isComposite ? String(localized: "Save Copy") : String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Discard"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: sender) { [self] response in
            switch response {
            case .alertFirstButtonReturn:
                // Exporting takes a moment, so close once the file is written.
                Task {
                    if await model.save() {
                        sender.close()
                    } else {
                        cancelClose()
                    }
                }
            case .alertSecondButtonReturn:
                discarding = true
                sender.close()
            default:
                cancelClose()
            }
        }
        return false
    }

    /// The window stays open: a quit waiting on it stops, and a Flatten waiting on it is dropped.
    private func cancelClose() {
        afterClose = nil
        resolveQuit(false)
    }

    func windowWillClose(_ notification: Notification) {
        resolveQuit(true)
        model.teardown()
        Self.open.removeAll { $0 === self }
        afterClose?()
        afterClose = nil
        EditorWindowController.releaseCachesIfNoEditorIsOpen()
    }
}
