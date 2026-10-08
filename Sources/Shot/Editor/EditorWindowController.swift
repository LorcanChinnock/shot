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
final class EditorWindowController: NSObject, NSWindowDelegate {
    private static var open: [EditorWindowController] = []

    private let model: EditorModel
    private let window: NSWindow
    private let canvas: EditorCanvasView
    private var discarding = false

    static func open(_ url: URL) {
        if let existing = open.first(where: { $0.model.fileURL == url }) {
            existing.show()
            return
        }
        guard let image = ImageCodec.image(at: url) else {
            let reason = FileManager.default.fileExists(atPath: url.path) ? "it isn't an image Shot can read" : "it doesn't exist"
            Toast.error("Cannot open \(url.lastPathComponent): \(reason)")
            return
        }
        let controller = EditorWindowController(model: EditorModel(fileURL: url, image: image, scale: ImageCodec.scale(ofFileAt: url)))
        open.append(controller)
        controller.show()
        log.notice("Editor opened: \(url.path)")
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

    func windowDidResignKey(_ notification: Notification) {
        canvas.releaseSpace()
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}
