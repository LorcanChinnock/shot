import AppKit
import os
import ShotCore

private let log = Logger.shot("editor")

private final class EditorWindow: NSWindow {
    var onCommand: ((String, Bool, Bool) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), onCommand?(key, flags.contains(.shift), flags.contains(.option)) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    private static var open: [EditorWindowController] = []
    static var isAnyOpen: Bool { !open.isEmpty }
    static var hasUnsavedChanges: Bool { open.contains { $0.model.isDirty } }

    /// Lets go of the renderer's images once no image or video editor is left to use them. Editors share the cache, so
    /// releasing it while one is open would only make that one draw its blurs and shadows again.
    static func releaseCachesIfNoEditorIsOpen() {
        if !isAnyOpen, !VideoEditorWindowController.isAnyOpen {
            AnnotationRenderer.releaseCaches()
        }
    }

    private let model: EditorModel
    /// The file this window was opened on: a version opened with its layers, or the image itself.
    private let opened: URL
    /// Run once the window has closed, so Flatten opens the version after any Save or Discard sheet.
    private var afterClose: (() -> Void)?
    private let window: NSWindow
    private let canvas: EditorCanvasView
    private var discarding = false
    /// Set while a quit waits on this window's Save / Discard / Cancel sheet; answers true once the window may go.
    private var quitReply: ((Bool) -> Void)?

    /// Asks about each window with unsaved changes in turn, bringing it forward. False if the user cancelled.
    static func confirmQuit() async -> Bool {
        for controller in open where controller.model.isDirty {
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

    /// `newCaptureStyle` styles a new capture's screenshot as the editor opens, as Use this style for new captures asks.
    /// A version with layers in the project store, or saved with marks Shot can rebuild, opens as its original with
    /// them live, so they can be changed. `flat` opens the file itself, as Flatten does.
    static func open(_ url: URL, newCaptureStyle: CopiedStyle? = nil, flat: Bool = false) {
        if let existing = open.first(where: { $0.opened == url || $0.model.version == url }) {
            existing.show()
            return
        }
        let saved = flat ? nil : VersionWriter.savedLayers(of: url, in: .app)
        let file = saved?.original ?? url
        guard let image = saved?.image ?? ImageCodec.image(at: url) else {
            let reason = FileManager.default.fileExists(atPath: url.path) ? String(localized: "it isn't an image Shot can read") : String(localized: "it doesn't exist")
            Toast.error("Can't open \(url.lastPathComponent): \(reason)")
            return
        }
        let model = EditorModel(
            fileURL: file, image: image, scale: ImageCodec.scale(ofFileAt: file), windowShadow: ImageCodec.hasWindowShadow(ofFileAt: file),
            newCaptureStyle: saved == nil ? newCaptureStyle : nil, layers: saved?.layers, version: url
        )
        let controller = EditorWindowController(model: model, opened: url)
        open.append(controller)
        controller.show()
        log.notice("Editor opened: \(url.path)\(saved == nil ? "" : " with its layers")")
    }

    private init(model: EditorModel, opened: URL) {
        self.model = model
        self.opened = opened
        canvas = EditorCanvasView(model: model)
        let pointSize = CGSize(width: CGFloat(model.document.base.width) / model.scale, height: CGFloat(model.document.base.height) / model.scale)
        let visible = (NSScreen.underPointer ?? NSScreen.screens[0]).visibleFrame
        let size = CGSize(width: min(max(pointSize.width + 60, 980), visible.width * 0.85), height: min(max(pointSize.height + 150, 480), visible.height * 0.85))
        let editorWindow = EditorWindow()
        window = editorWindow
        super.init()

        GlassWindow.make(editorWindow, size: size, title: model.fileURL.lastPathComponent, resizable: true) {
            EditorRootView(model: model, canvas: canvas)
        }
        window.delegate = self
        window.minSize = NSSize(width: 980, height: 420)

        editorWindow.onCommand = { [weak self] key, shift, option in
            self?.handleCommand(key, shift: shift, option: option) ?? false
        }
    }

    private func show() {
        GlassWindow.present(window)
        window.makeFirstResponder(canvas)
    }

    private func handleCommand(_ key: String, shift: Bool, option: Bool) -> Bool {
        // Typing in the canvas's text or a layer's name field keeps the editing shortcuts for the text.
        if canvas.isEditingText || window.firstResponder is NSText, key != "s", key != "w" {
            return false
        }
        switch key {
        case "z":
            shift ? model.redo() : model.undo()
        // ⌥⌘C and ⌥⌘V copy and paste a style, so they're matched before ⌘C and ⌘V.
        case "c" where option:
            model.copyStyle()
        case "v" where option:
            model.pasteStyle()
        case "c":
            // A selected annotation copies on its own; otherwise ⌘C copies the image, as the toolbar's Copy does.
            if !model.copySelection() {
                Task { await model.copy() }
            }
        case "v":
            return model.paste()
        case "d":
            return model.duplicateSelection()
        // ⌘+ is ⌘= without Shift on most layouts.
        case "=", "+":
            canvas.zoomIn()
        case "-":
            canvas.zoomOut()
        case "0":
            canvas.zoomToFit()
        case "1":
            canvas.zoomToActualSize()
        case "l":
            model.toggleLayers()
        case "i" where shift:
            model.showsImagePicker = true
        case "]":
            model.moveSelectedLayers(option ? .toFront : .forward)
        case "[":
            model.moveSelectedLayers(option ? .toBack : .backward)
        case "s":
            Task { await model.save() }
        case "w":
            window.performClose(nil)
        default:
            return false
        }
        return true
    }

    // The Edit menu's style items, which reach the editor through the key window's delegate.

    @objc func copyStyle(_ sender: Any?) {
        model.copyStyle()
    }

    @objc func pasteStyle(_ sender: Any?) {
        model.pasteStyle()
    }

    @objc func applyStyleToAllImages(_ sender: Any?) {
        model.applyStyleToAllImages()
    }

    /// Closes the layers and opens the saved version as a plain image. Unsaved changes are asked about first, and a
    /// Save makes the new version the one opened.
    @objc func flatten(_ sender: Any?) {
        afterClose = { [model] in
            if let version = model.version {
                Self.open(version, flat: true)
            }
        }
        window.performClose(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty, !discarding else {
            return true
        }
        guard sender.attachedSheet == nil else {
            cancelClose()
            return false
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save changes to \(model.fileURL.lastPathComponent)?")
        alert.informativeText = String(localized: "Your annotations are lost if you discard them.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Discard"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: sender) { [self] response in
            switch response {
            case .alertFirstButtonReturn:
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyStyle(_:)): model.styleTarget != nil
        case #selector(pasteStyle(_:)), #selector(applyStyleToAllImages(_:)): model.canPasteStyle && model.editingText == nil
        case #selector(flatten(_:)): model.version != nil
        default: true
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        canvas.releaseSpace()
    }

    func windowWillClose(_ notification: Notification) {
        resolveQuit(true)
        Self.open.removeAll { $0 === self }
        afterClose?()
        afterClose = nil
        Self.releaseCachesIfNoEditorIsOpen()
    }
}
