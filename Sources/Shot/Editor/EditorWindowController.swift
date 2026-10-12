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

    /// Lets go of the renderer's images once no image or video editor is left to use them. Editors share the cache, so
    /// releasing it while one is open would only make that one draw its blurs and shadows again.
    static func releaseCachesIfNoEditorIsOpen() {
        if !isAnyOpen, !VideoEditorWindowController.isAnyOpen {
            AnnotationRenderer.releaseCaches()
        }
    }

    private let model: EditorModel
    private let window: NSWindow
    private let canvas: EditorCanvasView
    private var discarding = false

    /// `newCaptureStyle` styles a new capture's screenshot as the editor opens, as Use this style for new captures asks.
    /// A version saved with marks Shot can rebuild opens as its original with those marks live, so they can be changed.
    static func open(_ url: URL, newCaptureStyle: CopiedStyle? = nil) {
        let saved = editableVersion(url)
        let file = saved?.original ?? url
        if let existing = open.first(where: { $0.model.fileURL == file }) {
            existing.show()
            return
        }
        guard let image = saved?.image ?? ImageCodec.image(at: url) else {
            let reason = FileManager.default.fileExists(atPath: url.path) ? "it isn't an image Shot can read" : "it doesn't exist"
            Toast.error("Can't open \(url.lastPathComponent): \(reason)")
            return
        }
        let model = EditorModel(
            fileURL: file, image: image, scale: ImageCodec.scale(ofFileAt: file), windowShadow: ImageCodec.hasWindowShadow(ofFileAt: file),
            newCaptureStyle: saved == nil ? newCaptureStyle : nil, layers: saved?.layers
        )
        let controller = EditorWindowController(model: model)
        open.append(controller)
        controller.show()
        log.notice("Editor opened: \(url.path)")
    }

    /// The original beside `url` and the live layers to open it with, when `url` is a version whose record can rebuild
    /// them and the original is still there.
    private static func editableVersion(_ url: URL) -> (original: URL, image: CGImage, layers: (annotations: [Annotation], canvas: CGRect))? {
        guard let record = ImageCodec.record(ofFileAt: url), let layers = record.editableLayers, let name = record.original else {
            return nil
        }
        let original = url.deletingLastPathComponent().appendingPathComponent(name)
        guard original != url, let image = ImageCodec.image(at: original) else {
            return nil
        }
        return (original, image, layers)
    }

    private init(model: EditorModel) {
        self.model = model
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
        if canvas.isEditingText && key != "s" && key != "w" {
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty, !discarding else {
            return true
        }
        guard sender.attachedSheet == nil else {
            return false
        }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(model.fileURL.lastPathComponent)?"
        alert.informativeText = "Your annotations are lost if you discard them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: sender) { [self] response in
            switch response {
            case .alertFirstButtonReturn:
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyStyle(_:)): model.styleTarget != nil
        case #selector(pasteStyle(_:)), #selector(applyStyleToAllImages(_:)): model.canPasteStyle && model.editingText == nil
        default: true
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        canvas.releaseSpace()
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
        Self.releaseCachesIfNoEditorIsOpen()
    }
}
