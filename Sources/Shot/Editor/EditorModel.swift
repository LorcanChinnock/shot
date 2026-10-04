import AppKit
import Observation
import ShotCore

extension EditorTool {
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .pen: "scribble"
        case .text: "textformat"
        case .note: "note.text"
        case .highlight: "highlighter"
        case .spotlight: "flashlight.on.fill"
        case .pixelate: "square.grid.3x3"
        case .blur: "drop.halffull"
        case .counter: "1.circle"
        case .crop: "crop"
        }
    }
}

@MainActor
@Observable
final class EditorModel {
    static let baseWidths = EditorStyle.widths

    let fileURL: URL
    let scale: CGFloat
    var document: EditorDocument
    // The tool, colours and width are remembered for the next editor window as they change.
    // They're not part of the document, so changing them is never an undo step.
    var tool: EditorTool {
        // Only the select tool selects, and the toolbar restyles the selection, so drop it when drawing.
        didSet {
            if tool != .select {
                selectedID = nil
            }
            rememberStyle()
        }
    }
    var colorIndex: Int {
        didSet { rememberStyle() }
    }
    /// Notes keep their own colour, pale yellow until the user picks another.
    var noteColorIndex: Int {
        didSet { rememberStyle() }
    }
    var widthIndex: Int {
        didSet { rememberStyle() }
    }
    var selectedID: UUID?
    var isDirty = false
    /// True while auto-redact looks for text to hide.
    var isRedacting = false
    /// The canvas's zoom, where 1 is actual size, for the zoom menu; the canvas view keeps it current.
    /// Zoom is view state, not part of the document, so it isn't undoable.
    var zoom: CGFloat = 1
    private(set) var undoStack = UndoStack<EditorSnapshot>()
    /// The annotation the arrow keys last moved, while that move is still the latest undo step,
    /// so holding an arrow key down undoes as one step.
    private var nudgedID: UUID?

    init(fileURL: URL, image: CGImage, scale: CGFloat, style: EditorStyle = Preferences().editorStyle) {
        self.fileURL = fileURL
        self.scale = scale
        document = EditorDocument(base: image, background: EditorDocument.defaultBackground(for: ImageFormat(fileExtension: fileURL.pathExtension)))
        tool = style.tool
        colorIndex = style.colorIndex
        noteColorIndex = style.noteColorIndex
        widthIndex = style.widthIndex
    }

    /// Select and crop aren't remembered, so the next window starts with the last drawing tool.
    private func rememberStyle() {
        Preferences.remember(EditorStyle(tool: tool, colorIndex: colorIndex, noteColorIndex: noteColorIndex, widthIndex: widthIndex))
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
    /// How far down and right a paste or duplicate lands from the original.
    var pasteStep: CGFloat { 10 * scale }
    var isJPEG: Bool { ImageFormat(fileExtension: fileURL.pathExtension) == .jpeg }

    /// Call before every change so it can be undone.
    func recordUndo() {
        undoStack.record(document.snapshot)
        nudgedID = nil
        isDirty = true
    }

    func undo() {
        nudgedID = nil
        if let previous = undoStack.undo(from: document.snapshot) {
            document.restore(previous)
            selectedID = nil
            isDirty = true
        }
    }

    func redo() {
        nudgedID = nil
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
        nudgedID = nil
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

    /// Moves the selection by one pixel, or ten when `large`, growing the canvas if it reaches past the edge.
    /// A `repeated` press (the key held down) joins the undo step of the press before it.
    func nudgeSelection(_ direction: NudgeDirection, large: Bool, repeated: Bool) {
        guard let selectedID = selection?.id else {
            return
        }
        if !repeated || nudgedID != selectedID {
            recordUndo()
        }
        nudgedID = selectedID
        document.move(selectedID, by: direction.offset(large: large), margin: canvasMargin)
    }

    /// Adds an offset copy of `annotation` as one undoable step and selects it.
    private func insertCopy(of annotation: Annotation) {
        recordUndo()
        let id = document.paste(annotation, step: pasteStep, margin: canvasMargin)
        tool = .select
        selectedID = id
    }

    /// Returns false if nothing is selected.
    func duplicateSelection() -> Bool {
        guard let selection else {
            return false
        }
        insertCopy(of: selection)
        return true
    }

    /// Pastes a copied annotation. Returns false if the pasteboard doesn't hold one.
    func paste() -> Bool {
        let annotation: Annotation?
        do {
            annotation = try Clipboard.annotation()
        } catch {
            Toast.show("Could not paste: \(error.localizedDescription)")
            return true
        }
        guard let annotation else {
            return false
        }
        insertCopy(of: annotation)
        return true
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

    /// Copies the selected annotation. Returns false if nothing is selected.
    func copySelection() -> Bool {
        guard let selection else {
            return false
        }
        do {
            try Clipboard.copy(annotation: selection)
            Toast.show("Copied annotation")
        } catch {
            Toast.show("Could not copy: \(error.localizedDescription)")
        }
        return true
    }

    /// Copies the flattened image.
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
