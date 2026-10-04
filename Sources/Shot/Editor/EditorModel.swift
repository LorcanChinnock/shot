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
        document = EditorDocument(base: image, background: EditorDocument.defaultBackground(for: ImageFormat(fileExtension: fileURL.pathExtension)))
    }

    var color: RGBA { RGBA.presets[colorIndex] }
    var lineWidth: CGFloat { Self.baseWidths[widthIndex] * scale }
    var fontSize: CGFloat { lineWidth * 6 }
    /// Space kept between an annotation and a canvas edge that grew to hold it.
    var canvasMargin: CGFloat { 16 * scale }
    var isJPEG: Bool { ImageFormat(fileExtension: fileURL.pathExtension) == .jpeg }

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

    /// Adds `annotation` as one undoable step, growing the canvas if it reaches past the edge.
    func add(_ annotation: Annotation) {
        recordUndo()
        document.annotations.append(annotation)
        document.grow(toFit: annotation, margin: canvasMargin)
    }

    func fitToContent() {
        edit { $0.fitToContent(margin: canvasMargin) }
    }

    func trimToImage() {
        edit { $0.trimToImage() }
    }

    func setBackground(_ background: RGBA?) {
        edit { $0.background = background }
    }

    /// Applies `change` as one undoable step, or does nothing if it leaves the document as it was.
    private func edit(_ change: (inout EditorDocument) -> Void) {
        let before = document.snapshot
        change(&document)
        guard document.snapshot != before else {
            return
        }
        undoStack.record(before)
        isDirty = true
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
        guard let image = AnnotationRenderer.flatten(document), let png = ImageCodec.data(from: image, scale: scale) else {
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
        guard let data = format == .png ? result.png : ImageCodec.data(from: result.image, scale: scale, format: format) else {
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
