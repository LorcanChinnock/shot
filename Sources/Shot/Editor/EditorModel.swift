import AppKit
import Observation
import ShotCore

enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rect, ellipse, text, highlight, pixelate, counter, crop

    var id: String { rawValue }

    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rect: "r"
        case .ellipse: "o"
        case .text: "t"
        case .highlight: "h"
        case .pixelate: "p"
        case .counter: "n"
        case .crop: "c"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .highlight: "highlighter"
        case .pixelate: "square.grid.3x3"
        case .counter: "1.circle"
        case .crop: "crop"
        }
    }

    var title: String { rawValue.capitalized }
}

@MainActor
@Observable
final class EditorModel {
    static let baseWidths: [CGFloat] = [2, 4, 8]

    let fileURL: URL
    let scale: CGFloat
    var document: EditorDocument
    var tool: EditorTool = .arrow
    var colorIndex = 0
    var widthIndex = 1
    var selectedID: UUID?
    var isDirty = false
    private(set) var undoStack = UndoStack<EditorSnapshot>()

    init(fileURL: URL, image: CGImage, scale: CGFloat) {
        self.fileURL = fileURL
        self.scale = scale
        document = EditorDocument(base: image)
    }

    var color: RGBA { RGBA.presets[colorIndex] }
    var lineWidth: CGFloat { Self.baseWidths[widthIndex] * scale }
    var fontSize: CGFloat { lineWidth * 6 }

    /// Call before every change so it can be undone.
    func recordUndo() {
        undoStack.record(document.snapshot)
        isDirty = true
    }

    func undo() {
        if let previous = undoStack.undo(from: document.snapshot) {
            document.restore(previous)
            selectedID = nil
            isDirty = true
        }
    }

    func redo() {
        if let next = undoStack.redo(from: document.snapshot) {
            document.restore(next)
            selectedID = nil
            isDirty = true
        }
    }

    func deleteSelection() {
        guard let selectedID else {
            return
        }
        recordUndo()
        document.annotations.removeAll { $0.id == selectedID }
        self.selectedID = nil
    }

    func flattened() -> (image: CGImage, png: Data)? {
        guard let image = AnnotationRenderer.flatten(document), let png = PNG.data(from: image, scale: scale) else {
            return nil
        }
        return (image, png)
    }


    func copy() {
        guard let result = flattened() else {
            Toast.show("Could not render image")
            return
        }
        Clipboard.copy(png: result.png, image: result.image)
        Toast.show("Copied")
    }

    @discardableResult
    func save() -> Bool {
        guard let result = flattened() else {
            Toast.show("Could not render image")
            return false
        }
        let format = ImageFormat(fileExtension: fileURL.pathExtension)
        guard let data = format == .png ? result.png : PNG.data(from: result.image, scale: scale, format: format) else {
            Toast.show("Could not render image")
            return false
        }
        do {
            try data.write(to: fileURL, options: .atomic)
            Clipboard.copy(png: result.png, image: result.image)
            isDirty = false
            Toast.show("Saved and copied")
            return true
        } catch {
            Toast.show("Save failed: \(error.localizedDescription)")
            return false
        }
    }
}
