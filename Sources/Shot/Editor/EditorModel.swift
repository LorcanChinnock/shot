import AppKit
import Observation
import ShotCore

enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rect, ellipse, text, note, highlight, pixelate, blur, counter, crop

    var id: String { rawValue }

    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rect: "r"
        case .ellipse: "o"
        case .text: "t"
        case .note: "s"
        case .highlight: "h"
        case .pixelate: "p"
        case .blur: "b"
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
        case .note: "note.text"
        case .highlight: "highlighter"
        case .pixelate: "square.grid.3x3"
        case .blur: "drop.halffull"
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
    var tool: EditorTool = .arrow {
        // Only the select tool selects, and the toolbar restyles the selection, so drop it when drawing.
        didSet {
            if tool != .select {
                selectedID = nil
            }
        }
    }
    var colorIndex = 0
    /// Notes keep their own colour, pale yellow until the user picks another.
    var noteColorIndex = 2
    var widthIndex = 1
    var selectedID: UUID?
    var isDirty = false
    /// True while auto-redact looks for text to hide.
    var isRedacting = false
    private(set) var undoStack = UndoStack<EditorSnapshot>()

    init(fileURL: URL, image: CGImage, scale: CGFloat) {
        self.fileURL = fileURL
        self.scale = scale
        document = EditorDocument(base: image, background: EditorDocument.defaultBackground(for: ImageFormat(fileExtension: fileURL.pathExtension)))
    }

    var color: RGBA { RGBA.presets[colorIndex] }
    var noteColor: RGBA { RGBA.presets[noteColorIndex] }

    var selection: Annotation? {
        selectedID.flatMap { id in document.annotations.first { $0.id == id } }
    }

    /// The colour the palette shows and sets: the selection's colour, else the note colour while the
    /// note tool is active, else the colour for the next annotation.
    var paletteIndex: Int {
        get {
            if let selection {
                return RGBA.presets.firstIndex(of: selection.color) ?? -1
            }
            return tool == .note ? noteColorIndex : colorIndex
        }
        set {
            if selection != nil {
                restyleSelection { $0.color = RGBA.presets[newValue] }
            } else if tool == .note {
                noteColorIndex = newValue
            } else {
                colorIndex = newValue
            }
        }
    }

    /// The width the toolbar shows and sets: the selection's, else the width for the next annotation.
    var lineWidthIndex: Int {
        get {
            if let selection {
                return Self.baseWidths.firstIndex { abs($0 * scale - selection.lineWidth) < 0.01 } ?? -1
            }
            return widthIndex
        }
        set {
            if selection != nil {
                restyleSelection { $0.setLineWidth(Self.baseWidths[newValue] * scale) }
            } else {
                widthIndex = newValue
            }
        }
    }

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

    /// Sets a text annotation's or note's text as one undoable step; empty text deletes it.
    func setText(_ id: UUID, to string: String) {
        edit { doc in
            guard let index = doc.annotations.firstIndex(where: { $0.id == id }) else {
                return
            }
            if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                doc.annotations.remove(at: index)
            } else {
                doc.annotations[index].setText(string)
                doc.grow(toFit: doc.annotations[index], margin: canvasMargin)
            }
        }
        if !document.annotations.contains(where: { $0.id == id }), selectedID == id {
            selectedID = nil
        }
    }

    /// Changes the selected annotation as one undoable step, growing the canvas if it now reaches past the edge.
    private func restyleSelection(_ change: (inout Annotation) -> Void) {
        guard let selectedID else {
            return
        }
        edit { doc in
            guard let index = doc.annotations.firstIndex(where: { $0.id == selectedID }) else {
                return
            }
            change(&doc.annotations[index])
            doc.grow(toFit: doc.annotations[index], margin: canvasMargin)
        }
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

    /// Covers the emails, phone numbers, card numbers and IP addresses in the image, as one undoable step.
    /// It switches to the select tool so each region can be checked and deleted before saving.
    func autoRedact(_ style: RedactionStyle) {
        guard !isRedacting else {
            return
        }
        isRedacting = true
        let doc = document
        Task {
            defer { isRedacting = false }
            let regions: [CGRect]
            do {
                regions = try await Redaction.regions(in: doc.base)
            } catch {
                Toast.show("Could not read the image: \(error.localizedDescription)")
                return
            }
            // The document may have changed while the text was read, so check against it as it is now.
            let added = document.redactions(covering: regions, style: style, color: color, lineWidth: lineWidth)
            guard !added.isEmpty else {
                Toast.show(regions.isEmpty ? "Found nothing to redact" : "Nothing new to redact")
                return
            }
            edit { $0.annotations += added }
            tool = .select
            Toast.show(added.count == 1 ? "Redacted 1 item" : "Redacted \(added.count) items")
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
