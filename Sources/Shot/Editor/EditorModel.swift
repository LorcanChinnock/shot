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
            } else {
                commitPendingText?()
            }
            rememberStyle { $0.tool = tool }
        }
    }
    var color: RGBA {
        didSet { rememberStyle { $0.color = color } }
    }
    /// Notes keep their own colour, pale yellow until the user picks another.
    var noteColor: RGBA {
        didSet { rememberStyle { $0.noteColor = noteColor } }
    }
    /// What new rectangles and ellipses are filled with; `nil` leaves them unfilled.
    var fill: RGBA? {
        didSet { rememberStyle { $0.fill = fill } }
    }
    /// Custom colours picked lately, newest first, shared by the border and fill palettes.
    private(set) var recentColors: [RGBA] {
        didSet { rememberStyle { $0.recentColors = recentColors } }
    }
    var widthIndex: Int {
        didSet { rememberStyle { $0.widthIndex = widthIndex } }
    }
    var selectedID: UUID?
    /// The note whose text field is open, with the colour picked for it so far; it may not be in the document yet.
    var editingNote: Annotation?
    var isDirty = false
    /// What the document looked like when it was last saved, so undoing back to it leaves the editor clean.
    @ObservationIgnored private var savedSnapshot: EditorSnapshot
    /// Set by the canvas: turns the text or note still being typed into an annotation.
    var commitPendingText: (() -> Void)?
    /// True while auto-redact looks for text to hide.
    var isRedacting = false
    /// The canvas's zoom, where 1 is actual size, for the zoom menu; the canvas view keeps it current.
    /// Zoom is view state, not part of the document, so it isn't undoable.
    var zoom: CGFloat = 1
    private(set) var undoStack = UndoStack<EditorSnapshot>()
    /// The annotation the arrow keys last moved, while that move is still the latest undo step,
    /// so holding an arrow key down undoes as one step.
    private var nudgedID: UUID?
    /// Which selection property a custom colour pick last changed, while that is still the latest undo step,
    /// so dragging through the colour panel undoes as one step.
    private var pickedKey: String?
    private var recentTask: Task<Void, Never>?

    init(fileURL: URL, image: CGImage, scale: CGFloat, style: EditorStyle = Preferences().editorStyle) {
        self.fileURL = fileURL
        self.scale = scale
        let document = EditorDocument(base: image, background: EditorDocument.defaultBackground(for: ImageFormat(fileExtension: fileURL.pathExtension)))
        self.document = document
        savedSnapshot = document.snapshot
        tool = style.tool
        color = style.color
        noteColor = style.noteColor
        fill = style.fill
        recentColors = style.recentColors
        widthIndex = style.widthIndex
    }

    /// Saves only the value that changed, so another open editor's choices aren't overwritten with this
    /// window's older ones. Select and crop aren't remembered, so the next window starts with the last drawing tool.
    private func rememberStyle(_ change: (inout EditorStyle) -> Void) {
        var style = Preferences().editorStyle
        change(&style)
        Preferences.remember(style)
    }

    var selection: Annotation? {
        selectedID.flatMap { id in document.annotations.first { $0.id == id } }
    }

    /// The colour the palette shows and sets: the selection's colour, else the note colour while the
    /// note tool is active, else the colour for the next annotation.
    var paletteColor: RGBA {
        get {
            editingNote?.color ?? selection?.color ?? (tool == .note ? noteColor : color)
        }
        set {
            if editingNote != nil {
                setEditingNoteColor(newValue)
            } else if selection != nil {
                restyleSelection { $0.color = newValue }
            } else if tool == .note {
                noteColor = newValue
            } else {
                color = newValue
            }
        }
    }

    /// True when the toolbar offers a fill: a rectangle or ellipse is selected, or is the tool.
    var showsFill: Bool {
        selection?.supportsFill ?? (tool == .rect || tool == .ellipse)
    }

    /// The fill the toolbar shows and sets, `nil` for none: the selection's, else the fill for the next shape.
    var paletteFill: RGBA? {
        get {
            selection != nil ? selection?.fill : fill
        }
        set {
            if selection != nil {
                restyleSelection { $0.fill = newValue }
            } else {
                fill = newValue
            }
        }
    }

    /// Recolours the note being typed. The document picks it up when the note is committed.
    /// A new note also sets the colour for the next one.
    private func setEditingNoteColor(_ colour: RGBA) {
        guard let note = editingNote else {
            return
        }
        editingNote?.color = colour
        if !document.annotations.contains(where: { $0.id == note.id }) {
            noteColor = colour
        }
    }

    /// Sets the border colour, or the fill, to one picked from the colour panel, which reports every
    /// change as the user drags. It's one undo step, and joins the recent colours once the drag settles.
    func pickCustom(_ colour: RGBA, forFill: Bool) {
        if editingNote != nil, !forFill {
            setEditingNoteColor(colour)
        } else if let selection {
            let key = "\(selection.id)-\(forFill)"
            restyleSelection(coalescing: key) { forFill ? ($0.fill = colour) : ($0.color = colour) }
        } else if forFill {
            fill = colour
        } else if tool == .note {
            noteColor = colour
        } else {
            color = colour
        }
        recentTask?.cancel()
        recentTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else {
                return
            }
            recentColors = EditorStyle.recents(adding: colour, to: recentColors)
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
        pickedKey = nil
        isDirty = true
    }

    func undo() {
        nudgedID = nil
        pickedKey = nil
        if let previous = undoStack.undo(from: document.snapshot) {
            document.restore(previous)
            selectedID = nil
            isDirty = document.snapshot != savedSnapshot
        }
    }

    func redo() {
        nudgedID = nil
        pickedKey = nil
        if let next = undoStack.redo(from: document.snapshot) {
            document.restore(next)
            selectedID = nil
            isDirty = document.snapshot != savedSnapshot
        }
    }

    /// Adds `annotation` as one undoable step, growing the canvas if it reaches past the edge.
    func add(_ annotation: Annotation) {
        recordUndo()
        document.annotations.append(annotation)
        document.grow(toFit: annotation, margin: canvasMargin)
    }

    /// Sets a text annotation's or note's text, and a note's colour, as one undoable step; empty text deletes it.
    func setText(_ id: UUID, to string: String, color: RGBA? = nil) {
        edit { doc in
            guard let index = doc.annotations.firstIndex(where: { $0.id == id }) else {
                return
            }
            if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                doc.annotations.remove(at: index)
            } else {
                doc.annotations[index].setText(string)
                if let color {
                    doc.annotations[index].color = color
                }
                doc.grow(toFit: doc.annotations[index], margin: canvasMargin)
            }
            doc.shrinkPadding(margin: canvasMargin)
        }
        if !document.annotations.contains(where: { $0.id == id }), selectedID == id {
            selectedID = nil
        }
    }

    /// Changes the selected annotation as one undoable step, growing the canvas if it now reaches past the edge.
    /// Calls with the same `key` in a row amend that step instead of adding another.
    private func restyleSelection(coalescing key: String? = nil, _ change: (inout Annotation) -> Void) {
        guard let selectedID else {
            return
        }
        let amend = key != nil && key == pickedKey
        func apply(_ doc: inout EditorDocument) {
            guard let index = doc.annotations.firstIndex(where: { $0.id == selectedID }) else {
                return
            }
            change(&doc.annotations[index])
            doc.grow(toFit: doc.annotations[index], margin: canvasMargin)
            doc.shrinkPadding(margin: canvasMargin)
        }
        if amend {
            apply(&document)
            isDirty = true
            return
        }
        let before = document.snapshot
        edit(apply)
        if document.snapshot != before {
            pickedKey = key
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
        pickedKey = nil
        isDirty = true
    }

    /// Covers the emails, phone numbers, card numbers and IP addresses in the image, as one undoable step.
    /// It switches to the select tool so each region can be checked and deleted before saving.
    func autoRedact(_ style: RedactionStyle) {
        guard !isRedacting else {
            return
        }
        isRedacting = true
        let source = document.redactionSource
        Task {
            defer { isRedacting = false }
            let regions: [CGRect]
            do {
                regions = try await Redaction.regions(in: source.image).map { $0.offsetBy(dx: source.origin.x, dy: source.origin.y) }
            } catch {
                Toast.error("Could not read the image: \(error.localizedDescription)")
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

    /// Pastes a copied annotation, else the image on the pasteboard beside the canvas.
    /// Returns false if the pasteboard holds neither.
    func paste() -> Bool {
        let annotation: Annotation?
        do {
            annotation = try Clipboard.annotation()
        } catch {
            Toast.error("Could not paste: \(error.localizedDescription)")
            return true
        }
        guard let annotation else {
            let images = Clipboard.images(on: .general)
            guard !images.isEmpty else {
                return false
            }
            addImages(images, at: nil)
            return true
        }
        insertCopy(of: annotation)
        return true
    }

    /// Adds the encoded images as one undoable step and selects the last. The first is centred on `point`
    /// and the rest step down and right from it; with no point, each goes beside the canvas, which grows to fit.
    func addImages(_ images: [Data], at point: CGPoint?) {
        let decoded = images.compactMap { data in ImageCodec.image(from: data).map { ($0, ImageCodec.scale(of: data)) } }
        guard !decoded.isEmpty else {
            Toast.error("Could not read the image")
            return
        }
        recordUndo()
        tool = .select
        for (index, (image, imageScale)) in decoded.enumerated() {
            let center = point.map { CGPoint(x: $0.x + pasteStep * CGFloat(index), y: $0.y + pasteStep * CGFloat(index)) }
            selectedID = document.addImage(image, scale: imageScale, documentScale: scale, centeredAt: center, margin: canvasMargin)
        }
    }

    func deleteSelection() {
        guard let selectedID else {
            return
        }
        recordUndo()
        document.annotations.removeAll { $0.id == selectedID }
        document.shrinkPadding(margin: canvasMargin)
        self.selectedID = nil
    }

    func flattened() -> (image: CGImage, png: Data)? {
        commitPendingText?()
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
            Toast.error("Could not copy: \(error.localizedDescription)")
        }
        return true
    }

    /// Copies the flattened image.
    func copy() {
        guard let result = flattened() else {
            Toast.error("Could not render image")
            return
        }
        Clipboard.copy(png: result.png, image: result.image)
        Toast.show("Copied")
    }

    @discardableResult
    func save() -> Bool {
        guard let result = flattened() else {
            Toast.error("Could not render image")
            return false
        }
        let format = ImageFormat(fileExtension: fileURL.pathExtension)
        guard let data = format == .png ? result.png : ImageCodec.data(from: result.image, scale: scale, format: format) else {
            Toast.error("Could not render image")
            return false
        }
        do {
            try data.write(to: FileNaming.nextVersionURL(of: fileURL), options: .atomic)
            Clipboard.copy(png: result.png, image: result.image)
            savedSnapshot = document.snapshot
            isDirty = false
            Toast.show("Saved and copied")
            return true
        } catch {
            Toast.error("Save failed: \(error.localizedDescription)")
            return false
        }
    }
}
