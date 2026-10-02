import AppKit
import os
import ShotCore
import SwiftUI

private let log = Logger(subsystem: "dev.lorcan.Shot", category: "editor")

private final class EditorWindow: NSWindow {
    var onCommand: ((String, Bool) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), onCommand?(key, flags.contains(.shift)) == true {
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

    static func open(_ url: URL) {
        if let existing = open.first(where: { $0.model.fileURL == url }) {
            existing.show()
            return
        }
        guard let image = PNG.image(at: url) else {
            Toast.show("Cannot open \(url.lastPathComponent)")
            return
        }
        let controller = EditorWindowController(model: EditorModel(fileURL: url, image: image, scale: PNG.scale(ofFileAt: url)))
        open.append(controller)
        controller.show()
        log.notice("Editor opened: \(url.path, privacy: .public)")
    }

    private init(model: EditorModel) {
        self.model = model
        canvas = EditorCanvasView(model: model)
        let pointSize = CGSize(width: CGFloat(model.document.base.width) / model.scale, height: CGFloat(model.document.base.height) / model.scale)
        let visible = (NSScreen.underPointer ?? NSScreen.screens[0]).visibleFrame
        let size = CGSize(width: min(max(pointSize.width + 40, 820), visible.width * 0.85), height: min(max(pointSize.height + 80, 420), visible.height * 0.85))
        let editorWindow = EditorWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window = editorWindow
        super.init()

        window.title = model.fileURL.lastPathComponent
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 820, height: 320)

        let toolbar = NSHostingView(rootView: EditorToolbar(model: model))
        let container = NSView()
        for view in [toolbar, canvas] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 40),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
        window.center()

        editorWindow.onCommand = { [weak self] key, shift in
            self?.handleCommand(key, shift: shift) ?? false
        }
    }

    private func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    private func handleCommand(_ key: String, shift: Bool) -> Bool {
        if canvas.isEditingText && key != "s" && key != "w" {
            return false
        }
        switch key {
        case "z":
            shift ? model.redo() : model.undo()
        case "c":
            model.copy()
        case "s":
            model.save()
        case "w":
            window.performClose(nil)
        default:
            return false
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(model.fileURL.lastPathComponent)?"
        alert.informativeText = "Your annotations are lost if you discard them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return model.save()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}
