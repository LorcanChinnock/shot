import AppKit
import Observation
import ShotCore

extension EditorTool {
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .shape: "square.on.circle"
        case .pen: "scribble"
        case .text: "textformat"
        case .note: "note.text"
        case .highlight: "highlighter"
        case .spotlight: "flashlight.on.fill"
        case .redact: "eye.slash"
        case .counter: "1.circle"
        case .crop: "crop"
        }
    }

    /// What the tool does, for its tooltip.
    var summary: String {
        switch self {
        case .select: "Click an annotation to move, resize or restyle it."
        case .arrow: "Drag to point at something."
        case .line: "Drag to draw a straight line."
        case .shape: "Drag to draw a box, circle, star or other shape, outlined or filled."
        case .pen: "Drag to draw freehand."
        case .text: "Click to type a label."
        case .note: "Drag to add a sticky note."
        case .highlight: "Drag over text to mark it in yellow."
        case .spotlight: "Drag to dim or blur everything outside an area."
        case .redact: "Drag over private details to blur or pixelate them."
        case .counter: "Click to add numbered steps: 1, 2, 3…"
        case .crop: "Drag to choose the area to keep."
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
        // The toolbar restyles the selection, so drop it when changing tool: it's either picked with the
        // select tool or the annotation just drawn with another.
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
    /// What new shapes are filled with; `nil` leaves them unfilled.
    var fill: RGBA? {
        didSet { rememberStyle { $0.fill = fill } }
    }
    /// The outline of the next shape.
    var shape: BoxShape {
        didSet { rememberStyle { $0.shape = shape } }
    }
    var redaction: Redaction {
        didSet { rememberStyle { $0.redaction = redaction } }
    }
    /// The next spotlight's shape, and the effect and strength for the image's first one.
    var spotlight: SpotlightStyle {
        didSet { rememberStyle { $0.spotlight = spotlight } }
    }
    /// The last custom colour picked in each palette.
    private(set) var customColors: [ColorSlot: RGBA]
    var widthIndex: Int {
        didSet { rememberStyle { $0.widthIndex = widthIndex } }
    }
    var selectedID: UUID?
    /// The text or note whose text field is open, with the colour and size picked for it so far; it may not be in the document yet.
    var editingText: Annotation?
    var isDirty = false
    /// What the document looked like when it was last saved, so undoing back to it leaves the editor clean.
    @ObservationIgnored private var savedSnapshot: EditorSnapshot
    /// Set by the canvas: turns the text or note still being typed into an annotation.
    var commitPendingText: (() -> Void)?
    /// The canvas's zoom, where 1 is actual size, for the zoom menu; the canvas view keeps it current.
    /// Zoom is view state, not part of the document, so it isn't undoable.
    var zoom: CGFloat = 1
    private(set) var undoStack = UndoStack<EditorSnapshot>()
    /// The annotation the arrow keys last moved, while that move is still the latest undo step,
    /// so holding an arrow key down undoes as one step.
    private var nudgedID: UUID?
    /// Which property a custom colour pick or a style slider last changed, while that is still the latest undo step,
    /// so dragging through the colour panel or along a slider undoes as one step.
    private var pickedKey: String?
    private var isDraggingStyle = false

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
        shape = style.shape
        redaction = style.redaction
        spotlight = style.spotlight
        customColors = style.customColors
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

    /// The colour the palette shows and sets: the text being typed's, else the selection's, else the note
    /// colour while the note tool is active, else the colour for the next annotation.
    var paletteColor: RGBA {
        get {
            editingText?.color ?? selection?.color ?? (tool == .note ? noteColor : color)
        }
        set {
            if editingText != nil {
                setEditingColor(newValue)
                return
            }
            restyleSelection { $0.color = newValue }
            if stylesNextAnnotation {
                if tool == .note {
                    noteColor = newValue
                } else {
                    color = newValue
                }
            }
        }
    }

    /// True when the toolbar sets the style of the next annotation: nothing is selected, or the selection is the
    /// annotation just drawn, so fixing its style fixes the tool's too. One picked with the select tool restyles alone.
    private var stylesNextAnnotation: Bool {
        selection == nil || tool != .select
    }

    /// True when the toolbar offers a colour and width: the text being typed or the selection takes them, or else the tool does.
    var showsStyle: Bool {
        editingText != nil || (selection?.isStyled ?? tool.isStyled)
    }

    /// True when the width sets a text size, so the toolbar offers sizes rather than line widths.
    var sizesText: Bool {
        (editingText ?? selection)?.sizesText ?? tool.sizesText
    }

    /// True when the toolbar offers a fill: a shape is selected, or is the tool.
    var showsFill: Bool {
        selection?.supportsFill ?? (tool == .shape)
    }

    /// The outline the toolbar shows: the selected shape's, else the next shape's. `nil` when neither is a shape.
    var paletteShape: BoxShape? {
        if let selection {
            guard case let .shape(shape, _) = selection.kind else {
                return nil
            }
            return shape
        }
        return tool == .shape ? shape : nil
    }

    func setShape(_ newShape: BoxShape) {
        restyleSelection {
            if case let .shape(_, rect) = $0.kind {
                $0.kind = .shape(newShape, rect: rect)
            }
        }
        if stylesNextAnnotation {
            shape = newShape
        }
    }

    /// How the toolbar shows a redaction hiding: the selected one's, else the next one's. `nil` when neither is one.
    var paletteRedaction: Redaction? {
        if let selection {
            return selection.redaction
        }
        return tool == .redact ? redaction : nil
    }

    func setRedaction(_ newRedaction: Redaction) {
        restyleSelection { $0.setRedaction(newRedaction) }
        if stylesNextAnnotation {
            redaction = newRedaction
        }
    }

    /// The next spotlight's style: the chosen shape, with the effect and strength the image's spotlights already share.
    var nextSpotlightStyle: SpotlightStyle {
        let shared = document.spotlightStyle ?? spotlight
        return SpotlightStyle(shape: spotlight.shape, effect: shared.effect, strength: shared.strength)
    }

    /// The spotlight style the toolbar shows: the selected spotlight's, else the next one's. `nil` when neither is one.
    var paletteSpotlight: SpotlightStyle? {
        if let selection {
            guard case let .spotlight(_, style) = selection.kind else {
                return nil
            }
            return style
        }
        return tool == .spotlight ? nextSpotlightStyle : nil
    }

    func setSpotlightShape(_ newShape: BoxShape) {
        restyleSelection {
            if case let .spotlight(rect, style) = $0.kind {
                $0.kind = .spotlight(rect, style: SpotlightStyle(shape: newShape, effect: style.effect, strength: style.strength))
            }
        }
        if stylesNextAnnotation {
            spotlight.shape = newShape
        }
    }

    /// Sets the effect and strength of every spotlight in the image, since they share one dim, and of the next one.
    /// Changes during a drag of a style slider are one undo step.
    func setSpotlightLook(effect: SpotlightStyle.Effect, strength: Double) {
        spotlight.effect = effect
        spotlight.strength = strength
        edit(coalescing: isDraggingStyle ? "spotlight-look" : nil) { $0.setSpotlights(effect: effect, strength: strength) }
    }

    /// Call as a drag of a style slider starts and ends, so each drag is one undo step.
    func setDraggingStyle(_ dragging: Bool) {
        isDraggingStyle = dragging
        pickedKey = nil
    }

    /// The fill the toolbar shows and sets, `nil` for none: the selection's, else the fill for the next shape.
    var paletteFill: RGBA? {
        get {
            selection != nil ? selection?.fill : fill
        }
        set {
            restyleSelection { $0.fill = newValue }
            if stylesNextAnnotation {
                fill = newValue
            }
        }
    }

    /// Recolours the text or note being typed. The document picks it up when it's committed.
    /// New text or a new note also sets the colour for the next one.
    private func setEditingColor(_ colour: RGBA) {
        guard let text = editingText else {
            return
        }
        editingText?.color = colour
        if !document.annotations.contains(where: { $0.id == text.id }) {
            if case .note = text.kind {
                noteColor = colour
            } else {
                color = colour
            }
        }
    }

    /// Sets the border colour, or the fill, to one picked from the colour panel, which reports every
    /// change as the user drags. It's one undo step, and becomes the palette's last custom colour.
    func pickCustom(_ colour: RGBA, forFill: Bool) {
        if editingText != nil, !forFill {
            setEditingColor(colour)
        } else {
            if let selection {
                let key = "\(selection.id)-\(forFill)"
                restyleSelection(coalescing: key) { forFill ? ($0.fill = colour) : ($0.color = colour) }
            }
            if stylesNextAnnotation {
                if forFill {
                    fill = colour
                } else if tool == .note {
                    noteColor = colour
                } else {
                    color = colour
                }
            }
        }
        let slot = customSlot(forFill: forFill)
        customColors[slot] = colour
        rememberStyle { $0.customColors[slot] = colour }
    }

    /// The border or fill palette's last custom colour.
    func lastCustom(forFill: Bool) -> RGBA? {
        customColors[customSlot(forFill: forFill)]
    }

    private func customSlot(forFill: Bool) -> ColorSlot {
        ColorSlot(forFill: forFill, shown: editingText ?? selection, tool: tool)
    }

    /// The width the toolbar shows and sets: the text being typed's, else the selection's, else the width for the next annotation.
    var lineWidthIndex: Int {
        get {
            if let shown = editingText ?? selection {
                return Self.baseWidths.firstIndex { abs($0 * scale - shown.lineWidth) < 0.01 } ?? -1
            }
            return widthIndex
        }
        set {
            if let text = editingText {
                // Text resizes as it's typed; new text also sets the width for the next annotation.
                editingText?.setLineWidth(Self.baseWidths[newValue] * scale)
                if !document.annotations.contains(where: { $0.id == text.id }) {
                    widthIndex = newValue
                }
            } else {
                restyleSelection { $0.setLineWidth(Self.baseWidths[newValue] * scale) }
                if stylesNextAnnotation {
                    widthIndex = newValue
                }
            }
        }
    }

    var lineWidth: CGFloat { Self.baseWidths[widthIndex] * scale }
    var fontSize: CGFloat { lineWidth * 6 }
    var cornerRadius: CGFloat { Annotation.defaultCornerRadius * scale }
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

    /// Adds `annotation` as one undoable step, growing the canvas if it reaches past the edge, and selects it
    /// so the toolbar can fix its style until the next one is drawn.
    func add(_ annotation: Annotation) {
        recordUndo()
        document.annotations.append(annotation)
        document.grow(toFit: annotation, margin: canvasMargin)
        selectedID = annotation.id
    }

    /// Puts text or a note as it was typed and styled into the document as one undoable step: in place of the
    /// one its field was opened on, else as a new one. Empty text deletes it, or adds nothing.
    func commitText(_ edited: Annotation) {
        let isEmpty = (edited.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard document.annotations.contains(where: { $0.id == edited.id }) else {
            if !isEmpty {
                add(edited)
            }
            return
        }
        edit { doc in
            guard let index = doc.annotations.firstIndex(where: { $0.id == edited.id }) else {
                return
            }
            if isEmpty {
                doc.annotations.remove(at: index)
            } else {
                doc.annotations[index] = edited
                doc.grow(toFit: edited, margin: canvasMargin)
            }
            doc.shrinkPadding(margin: canvasMargin)
        }
        if !document.annotations.contains(where: { $0.id == edited.id }), selectedID == edited.id {
            selectedID = nil
        }
    }

    /// Changes the selected annotation as one undoable step, growing the canvas if it now reaches past the edge.
    /// Calls with the same `key` in a row amend that step instead of adding another.
    private func restyleSelection(coalescing key: String? = nil, _ change: (inout Annotation) -> Void) {
        guard let selectedID else {
            return
        }
        edit(coalescing: key) { doc in
            guard let index = doc.annotations.firstIndex(where: { $0.id == selectedID }) else {
                return
            }
            change(&doc.annotations[index])
            doc.grow(toFit: doc.annotations[index], margin: canvasMargin)
            doc.shrinkPadding(margin: canvasMargin)
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
    /// Calls with the same `key` in a row amend that step instead of adding another.
    private func edit(coalescing key: String? = nil, _ change: (inout EditorDocument) -> Void) {
        if key != nil, key == pickedKey {
            change(&document)
            isDirty = true
            return
        }
        let before = document.snapshot
        change(&document)
        guard document.snapshot != before else {
            return
        }
        undoStack.record(before)
        nudgedID = nil
        pickedKey = key
        isDirty = true
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
        let destination = FileNaming.nextVersionURL(of: fileURL)
        do {
            try data.write(to: destination, options: .atomic)
            Clipboard.copy(png: result.png, image: result.image)
            savedSnapshot = document.snapshot
            isDirty = false
            Toast.show("Saved as \(destination.lastPathComponent) and copied", duration: .seconds(3))
            return true
        } catch {
            Toast.error("Save failed: \(error.localizedDescription)")
            return false
        }
    }
}
