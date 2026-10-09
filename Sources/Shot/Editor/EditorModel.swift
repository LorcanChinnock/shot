import AppKit
import Observation
import ShotCore

extension EditorTool {
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .hand: "hand.raised"
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
        case .hand: "Drag to move around when zoomed in."
        case .arrow: "Drag to point at something."
        case .line: "Drag to draw a straight line."
        case .shape: "Drag to draw a box, circle, star or other shape, outlined or filled."
        case .pen: "Drag to draw freehand."
        case .text: "Click to type a label."
        case .note: "Drag to add a sticky note."
        case .highlight: "Drag over text to highlight it. Hold Shift for a straight line."
        case .spotlight: "Drag to dim or blur everything outside an area."
        case .redact: "Drag over private details to blur or pixelate them."
        case .counter: "Click to add numbered steps: 1, 2, 3…"
        case .crop: "Drag to choose the area to keep."
        }
    }
}

extension Annotation {
    var layerSymbol: String {
        switch kind {
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .shape: "square.on.circle"
        case .highlight, .marker: "highlighter"
        case .pixelate: "squareshape.split.3x3"
        case .blur: "drop.halffull"
        case .spotlight: "flashlight.on.fill"
        case .text: "textformat"
        case .counter: "1.circle"
        case .note: "note.text"
        case .freehand: "scribble"
        case .image: "photo"
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
    /// The highlighter keeps its own colour too, yellow until the user picks another.
    var highlightColor: RGBA {
        didSet { rememberStyle { $0.highlightColor = highlightColor } }
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
    var redactionAmount: CGFloat {
        didSet { rememberStyle { $0.redactionAmount = redactionAmount } }
    }
    /// The next spotlight's shape, and the effect and strength for the image's first one.
    var spotlight: SpotlightStyle {
        didSet { rememberStyle { $0.spotlight = spotlight } }
    }
    /// How the lines of the next text or note line up.
    var alignment: TextAlign {
        didSet { rememberStyle { $0.alignment = alignment } }
    }
    /// The last custom colour picked in each palette.
    private(set) var customColors: [ColorSlot: RGBA]
    var widthIndex: Int {
        didSet { rememberStyle { $0.widthIndex = widthIndex } }
    }
    /// The last shadow and border given to each kind, in points, which new ones of that kind start with.
    private var objectStyles: [StyleKind: ObjectStyle]
    /// The style Copy Style took last, in any editor window, which Paste Style puts on the selection.
    private static var copiedStyle: CopiedStyle?
    /// The layers picked, from the canvas or the layers panel. The toolbar styles an annotation only while it's the only one.
    var selectedIDs: Set<UUID> = []
    var selectedID: UUID? {
        get { selectedIDs.count == 1 ? selectedIDs.first : nil }
        set { selectedIDs = newValue.map { [$0] } ?? [] }
    }
    var showsLayers = UserDefaults.standard.bool(forKey: EditorModel.showsLayersKey)
    /// Whether the picker of images to place on the canvas is open.
    var showsImagePicker = false
    /// Whether the Style popover is open.
    var showsStylePopover = false
    private static let showsLayersKey = "editorShowsLayers"
    /// The text or note whose text field is open, with the colour and size picked for it so far; it may not be in the document yet.
    var editingText: Annotation?
    var isDirty = false
    /// What the document looked like when it was last saved, so undoing back to it leaves the editor clean.
    @ObservationIgnored private var savedSnapshot: EditorSnapshot
    @ObservationIgnored private var isSaving = false
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
        highlightColor = style.highlightColor
        fill = style.fill
        shape = style.shape
        redaction = style.redaction
        redactionAmount = style.redactionAmount
        spotlight = style.spotlight
        alignment = style.alignment
        customColors = style.customColors
        widthIndex = style.widthIndex
        objectStyles = style.objectStyles
    }

    /// Saves only the value that changed, so another open editor's choices aren't overwritten with this
    /// window's older ones. Select, hand and crop aren't remembered, so the next window starts with the last drawing tool.
    private func rememberStyle(_ change: (inout EditorStyle) -> Void) {
        var style = Preferences().editorStyle
        change(&style)
        Preferences.remember(style)
    }

    var selection: Annotation? {
        selectedID.flatMap { id in document.annotations.first { $0.id == id } }
    }

    // MARK: Layers

    /// The annotations frontmost first, as the layers panel lists them.
    var layers: [Annotation] { document.annotations.reversed() }

    var layerRows: [LayerRow] {
        layers.map { LayerRow(id: $0.id, name: $0.layerName, symbol: $0.layerSymbol, isHidden: $0.isHidden, isLocked: $0.isLocked) }
    }

    func toggleLayers() {
        showsLayers.toggle()
        UserDefaults.standard.set(showsLayers, forKey: Self.showsLayersKey)
    }

    /// Picks layers from the panel, which also switches to the select tool, as picking one on the canvas does.
    func selectLayers(_ ids: Set<UUID>) {
        if tool != .select {
            tool = .select
        }
        selectedIDs = ids.intersection(document.annotations.map(\.id))
    }

    func moveSelectedLayers(_ move: LayerMove) {
        guard !selectedIDs.isEmpty else {
            return
        }
        edit { $0.annotations = $0.annotations.moving(selectedIDs, move) }
    }

    /// Drops the layers at `offsets` of `layers` before the row at `destination`.
    func moveLayers(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let listed = layers
        let moved = Set(offsets.map { listed[$0].id })
        let index = LayerList.backToFrontIndex(movingOffsets: offsets, toOffset: destination, count: listed.count)
        edit { $0.annotations = $0.annotations.moving(moved, toIndex: index) }
    }

    func setHidden(_ hidden: Bool, _ ids: Set<UUID>) {
        edit { doc in
            for index in doc.annotations.indices where ids.contains(doc.annotations[index].id) {
                doc.annotations[index].isHidden = hidden
            }
        }
        if hidden {
            selectedIDs.subtract(ids)
        }
    }

    func setLocked(_ locked: Bool, _ ids: Set<UUID>) {
        edit { doc in
            for index in doc.annotations.indices where ids.contains(doc.annotations[index].id) {
                doc.annotations[index].isLocked = locked
            }
        }
    }

    func duplicateLayers(_ ids: Set<UUID>) {
        let copies = document.annotations.filter { ids.contains($0.id) }
        guard !copies.isEmpty else {
            return
        }
        recordUndo()
        tool = .select
        selectedIDs = Set(copies.map { document.paste($0, step: pasteStep, margin: canvasMargin) })
    }

    func deleteLayers(_ ids: Set<UUID>) {
        var removed: Set<UUID> = []
        edit { removed = $0.deleteLayers(ids, margin: canvasMargin) }
        selectedIDs.subtract(removed)
    }

    /// The colour the palette shows and sets: the text being typed's, else the selection's, else the colour for the tool's next annotation.
    var paletteColor: RGBA {
        get {
            editingText?.color ?? selection?.color ?? nextColor
        }
        set {
            if editingText != nil {
                setEditingColor(newValue)
                return
            }
            restyleSelection { $0.color = newValue }
            if stylesNextAnnotation {
                nextColor = newValue
            }
        }
    }

    /// The colour for the tool's next annotation: notes and the highlighter keep their own.
    var nextColor: RGBA {
        get {
            switch tool {
            case .note: noteColor
            case .highlight: highlightColor
            default: color
            }
        }
        set {
            switch tool {
            case .note: noteColor = newValue
            case .highlight: highlightColor = newValue
            default: color = newValue
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

    /// How strongly the toolbar shows a redaction hiding: the selected one's, else the next one's.
    var paletteRedactionAmount: CGFloat {
        selection?.redactionAmount(imageLength: CGFloat(max(document.base.width, document.base.height))) ?? redactionAmount
    }

    /// Sets how strongly the selected redaction, or the next one, hides. Changes during a drag of a style slider are one undo step.
    func setRedactionAmount(_ amount: CGFloat) {
        if let selection {
            restyleSelection(coalescing: isDraggingStyle ? "\(selection.id)-redaction-amount" : nil) { $0.setRedactionAmount(amount) }
        }
        if stylesNextAnnotation {
            redactionAmount = amount
        }
    }

    /// The next spotlight's style: the chosen shape and edge, with the effect and strength the image's spotlights already share.
    var nextSpotlightStyle: SpotlightStyle {
        let shared = document.spotlightStyle ?? spotlight
        return SpotlightStyle(shape: spotlight.shape, effect: shared.effect, strength: shared.strength, softEdge: spotlight.softEdge)
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
        restyleSelection { $0.restyleSpotlight { $0.shape = newShape } }
        if stylesNextAnnotation {
            spotlight.shape = newShape
        }
    }

    /// Changes during a drag of a style slider are one undo step.
    func setSpotlightSoftEdge(_ softEdge: Double) {
        restyleSelection(coalescing: isDraggingStyle ? "spotlight-edge" : nil) { $0.restyleSpotlight { $0.softEdge = softEdge } }
        if stylesNextAnnotation {
            spotlight.softEdge = softEdge
        }
    }

    /// Sets the effect and strength of every spotlight in the image, since they share one dim, and of the next one.
    /// Changes during a drag of a style slider are one undo step.
    func setSpotlightLook(effect: SpotlightStyle.Effect, strength: Double) {
        spotlight.effect = effect
        spotlight.strength = strength
        edit(coalescing: isDraggingStyle ? "spotlight-look" : nil) { $0.setSpotlights(effect: effect, strength: strength) }
    }

    // MARK: Object style

    /// What the Style popover changes: the selected image, mark or text, else the capture when nothing is selected. `nil`
    /// while text is typed or the selection can't take a style.
    var styleTarget: StyleTarget? {
        guard editingText == nil else {
            return nil
        }
        guard !selectedIDs.isEmpty else {
            return .capture
        }
        guard let selection, selection.takesObjectStyle, !selection.isLocked else {
            return nil
        }
        return .annotation(selection.id)
    }

    /// What the Style popover's target is, which decides what it offers.
    var targetStyleKind: StyleKind? {
        styleTarget.flatMap { document.styleKind(of: $0) }
    }

    /// Whether the target has see-through pixels, so the Style popover offers an outline.
    var targetHasTransparency: Bool {
        styleTarget.map { document.hasTransparency(of: $0) } ?? false
    }

    /// The style the Style popover shows: its target's.
    var targetStyle: ObjectStyle {
        styleTarget.map { document.style(of: $0) } ?? ObjectStyle()
    }

    /// The corner radius the Style popover shows, in points.
    var targetCornerRadius: CGFloat {
        styleTarget.map { document.cornerRadius(of: $0) / scale } ?? 0
    }

    /// A style the pointer is over in the Style popover, shown on the canvas in place of the target's until it moves off.
    /// It's not part of the document, so it's never an undo step.
    var stylePreview: ObjectStyle?

    /// The document with the style previewed, which the canvas draws.
    var previewDocument: EditorDocument {
        guard let stylePreview, let styleTarget else {
            return document
        }
        var doc = document
        doc.setStyle(stylePreview, of: styleTarget, margin: canvasMargin)
        return doc
    }

    /// Sets the target's shadow and border as one undo step.
    func setTargetStyle(_ style: ObjectStyle) {
        stylePreview = nil
        restyleTarget { $0 = style }
    }

    /// Changes during a drag of a style slider are one undo step.
    func setShadowElevation(_ points: CGFloat) {
        restyleTarget(coalescing: "shadow") { $0.shadow?.elevation = points * scale }
    }

    /// Changes during a drag of a style slider are one undo step.
    func setShadowOpacity(_ opacity: CGFloat) {
        restyleTarget(coalescing: "shadow") { $0.shadow?.opacity = opacity }
    }

    /// The colour a border picked from the custom colour editor had last, which its rainbow swatch applies again.
    private(set) var lastBorderColor = RGBA(1, 1, 1)

    /// A new `kind` border for the target, at the middle width, in the colour of the border it has, else white, or
    /// for text the ink that stands out from its colour.
    func newBorder(_ kind: Border.Kind) -> Border {
        guard kind != .hairline, let styleKind = targetStyleKind else {
            return .hairline
        }
        let widths = Border.widths(kind, on: styleKind)
        let textColor = styleKind == .text ? selection?.color.contrastingInk : nil
        let color = targetStyle.border?.color ?? textColor ?? RGBA(1, 1, 1)
        return Border(kind: kind, lineWidth: widths[widths.count / 2] * scale, color: color)
    }

    /// Sets the width of the target's solid border or outline to one of `Border.widths`, in points.
    func setBorderWidth(_ points: CGFloat) {
        restyleTarget { $0.border?.lineWidth = points * scale }
    }

    func setBorderColor(_ color: RGBA) {
        restyleTarget { $0.border?.color = color }
    }

    /// Sets the border's colour to one picked from the colour editor, which reports every change as the user drags.
    /// It's one undo step.
    func pickBorderColor(_ color: RGBA) {
        lastBorderColor = color
        restyleTarget(coalescing: "border-color", whileDragging: false) { $0.border?.color = color }
    }

    /// Changes during a drag of a style slider are one undo step.
    func setTargetCornerRadius(_ points: CGFloat) {
        guard let styleTarget else {
            return
        }
        edit(coalescing: isDraggingStyle ? "\(styleTarget)-corners" : nil) { $0.setCornerRadius(points * scale, of: styleTarget) }
    }

    /// Changes the target's style as one undo step, growing the canvas to hold it, and remembers it for the next one of
    /// its kind. While a style slider is dragged, or always unless `whileDragging`, calls with the same `key` amend that step.
    private func restyleTarget(coalescing key: String? = nil, whileDragging: Bool = true, _ change: (inout ObjectStyle) -> Void) {
        guard let styleTarget, let kind = targetStyleKind else {
            return
        }
        var style = document.style(of: styleTarget)
        change(&style)
        edit(coalescing: isDraggingStyle || !whileDragging ? key.map { "\(styleTarget)-\($0)" } : nil) { $0.setStyle(style, of: styleTarget, margin: canvasMargin) }
        // The screenshot isn't remembered: new captures always start plain.
        if kind != .capture {
            let remembered = document.style(of: styleTarget).scaled(by: 1 / scale)
            objectStyles[kind] = remembered
            rememberStyle { $0.objectStyles[kind] = remembered }
        }
    }

    /// The style a new annotation of `kind` starts with: the last one given to that kind, else none.
    private func startingStyle(for kind: StyleKind) -> ObjectStyle {
        EditorStyle(objectStyles: objectStyles).objectStyle(for: kind, scale: scale)
    }

    /// Copies the style of the selection, or of the screenshot when nothing is selected, for Paste Style.
    func copyStyle() {
        guard let styleTarget, let copied = document.copyStyle(of: styleTarget, scale: scale) else {
            Toast.error("Select an image, shape, arrow or text to copy its style")
            return
        }
        Self.copiedStyle = copied
        Toast.show("Copied style")
    }

    var canPasteStyle: Bool { Self.copiedStyle != nil }

    /// Puts the copied style on every selected annotation that takes one, or on the screenshot when nothing is selected,
    /// as one undo step. Each takes only what it can have.
    func pasteStyle() {
        guard let copied = Self.copiedStyle, editingText == nil else {
            return
        }
        let targets: [StyleTarget] = selectedIDs.isEmpty ? [.capture] : document.annotations.filter { selectedIDs.contains($0.id) }.map { .annotation($0.id) }
        edit { $0.pasteStyle(copied, to: targets, scale: scale, margin: canvasMargin) }
    }

    /// Puts the copied style on the screenshot and every placed image as one undo step.
    func applyStyleToAllImages() {
        guard let copied = Self.copiedStyle, editingText == nil else {
            return
        }
        edit { $0.pasteStyle(copied, to: $0.imageStyleTargets, scale: scale, margin: canvasMargin) }
    }

    /// Call as a drag of a style slider starts and ends, so each drag is one undo step.
    func setDraggingStyle(_ dragging: Bool) {
        isDraggingStyle = dragging
        pickedKey = nil
    }

    /// The alignment the toolbar shows: the text being typed's, else the selection's, else the next text's or note's.
    /// `nil` when none of them is text or a note.
    var paletteAlignment: TextAlign? {
        if let shown = editingText ?? selection {
            return shown.alignsText ? shown.alignment : nil
        }
        return tool == .text || tool == .note ? alignment : nil
    }

    func setAlignment(_ newAlignment: TextAlign) {
        if let text = editingText {
            editingText?.alignment = newAlignment
            if !document.annotations.contains(where: { $0.id == text.id }) {
                alignment = newAlignment
            }
            return
        }
        restyleSelection { $0.alignment = newAlignment }
        if stylesNextAnnotation {
            alignment = newAlignment
        }
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
                } else {
                    nextColor = colour
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
    /// so the toolbar can fix its style until the next one is drawn. A mark or text starts with the last style given to its kind.
    func add(_ annotation: Annotation) {
        recordUndo()
        var annotation = annotation
        if let kind = annotation.styleKind, annotation.style.isEmpty {
            annotation.style = startingStyle(for: kind)
        }
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
        guard let selectedID, selection?.isLocked != true else {
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
        guard let selectedID = selection?.id, selection?.isLocked != true else {
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
        guard !selectedIDs.isEmpty else {
            return false
        }
        duplicateLayers(selectedIDs)
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
        let style = startingStyle(for: .image)
        for (index, (image, imageScale)) in decoded.enumerated() {
            let center = point.map { CGPoint(x: $0.x + pasteStep * CGFloat(index), y: $0.y + pasteStep * CGFloat(index)) }
            let id = document.addImage(image, scale: imageScale, documentScale: scale, centeredAt: center, margin: canvasMargin)
            // It starts with the last style given to an image, but for an outline it has no see-through pixels for.
            if !style.isEmpty {
                document.setStyle(style, of: .annotation(id), margin: canvasMargin)
            }
            selectedID = id
        }
    }

    /// Places the images in the files at `urls` beside the canvas, as pasting them does.
    func addImageFiles(_ urls: [URL]) {
        addImages(urls.compactMap { try? Data(contentsOf: $0) }, at: nil)
    }

    func deleteSelection() {
        deleteLayers(selectedIDs)
    }

    private func rendered(as format: ImageFormat = .png) async -> (image: CGImage, png: Data, file: Data)? {
        let document = document, scale = scale
        let result = await Task.detached { () -> (image: SendableImage, png: Data, file: Data)? in
            guard let image = AnnotationRenderer.flatten(document), let png = ImageCodec.data(from: image, scale: scale) else {
                return nil
            }
            guard let file = format == .png ? png : ImageCodec.data(from: image, scale: scale, format: format) else {
                return nil
            }
            return (SendableImage(image), png, file)
        }.value
        return result.map { ($0.image.image, $0.png, $0.file) }
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
    func copy() async {
        commitPendingText?()
        guard let result = await rendered() else {
            Toast.error("Could not render image")
            return
        }
        Clipboard.copy(png: result.png)
        Toast.show("Copied")
    }

    /// Returns false if the save failed or another is still running.
    @discardableResult
    func save() async -> Bool {
        guard !isSaving else {
            return false
        }
        isSaving = true
        defer { isSaving = false }
        commitPendingText?()
        let snapshot = document.snapshot
        guard let result = await rendered(as: ImageFormat(fileExtension: fileURL.pathExtension)) else {
            Toast.error("Could not render image")
            return false
        }
        let destination = FileNaming.nextVersionURL(of: fileURL)
        do {
            try result.file.write(to: destination, options: .atomic)
            Clipboard.copy(png: result.png)
            savedSnapshot = snapshot
            isDirty = document.snapshot != snapshot
            Toast.show("Saved as \(destination.lastPathComponent) and copied", duration: .seconds(3))
            return true
        } catch {
            Toast.error("Save failed: \(error.localizedDescription)")
            return false
        }
    }
}
