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
        case .select: String(localized: "Click an annotation to move, resize or restyle it.")
        case .hand: String(localized: "Drag to move around when zoomed in.")
        case .arrow: String(localized: "Drag to point at something.")
        case .line: String(localized: "Drag to draw a straight line.")
        case .shape: String(localized: "Drag to draw a box, circle, star or other shape, outlined or filled.")
        case .pen: String(localized: "Drag to draw freehand.")
        case .text: String(localized: "Click to type a label.")
        case .note: String(localized: "Drag to add a sticky note.")
        case .highlight: String(localized: "Drag over text to highlight it. Hold Shift for a straight line.")
        case .spotlight: String(localized: "Drag to dim or blur everything outside an area.")
        case .redact: String(localized: "Drag over private details to blur or pixelate them.")
        case .counter: String(localized: "Click to add numbered steps: 1, 2, 3…")
        case .crop: String(localized: "Drag the handles to choose the area to keep, of the whole picture or the placed image selected. Return applies it, Esc cancels.")
        }
    }
}

@MainActor
@Observable
final class EditorModel {
    static let baseWidths = EditorStyle.widths

    let fileURL: URL
    let scale: CGFloat
    /// The saved version whose layers the editor shows, the one it opened or last saved, which Flatten opens as a
    /// plain image; `nil` until there is one.
    private(set) var version: URL?
    /// The file the document's base image is, when that isn't `fileURL`: the original the opened version was saved from, or
    /// the copy kept when a save went over it. Saving keeps the layers on it.
    private(set) var pristine: URL?
    /// Whether `version` is a file a save went over, so `pristine` is what it was before and Revert to Original can put it back.
    private(set) var canRevert = false
    private(set) var document: EditorDocument
    // The tool, colours and width are remembered for the next editor window as they change.
    // They're not part of the document, so changing them is never an undo step.
    var tool: EditorTool {
        // The toolbar restyles the selection, so drop it when changing tool: it's either picked with the
        // select tool or the annotation just drawn with another.
        didSet {
            // A placed image picked as the crop tool is taken up gets a crop of its own.
            let imageToCrop = tool == .crop && oldValue != .crop ? (pendingCropImage ?? croppableSelection) : nil
            pendingCropImage = nil
            if tool != .select {
                selectedID = nil
            } else {
                commitPendingText?()
            }
            if tool == .crop, oldValue != .crop {
                beginCrop(from: oldValue, image: imageToCrop)
            } else if oldValue == .crop, tool != .crop {
                finishCrop()
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
    /// Where the next note's text sits in it.
    var verticalAlignment: VerticalTextAlign {
        didSet { rememberStyle { $0.verticalAlignment = verticalAlignment } }
    }
    /// The last custom colour picked in each palette.
    private(set) var customColors: [ColorSlot: RGBA]
    var widthIndex: Int {
        didSet { rememberStyle { $0.widthIndex = widthIndex } }
    }
    /// The last shadow and border given to each kind, in points, which new ones of that kind start with.
    private var objectStyles: [StyleKind: ObjectStyle]
    /// Bumped when this window changes Use this style for new captures, so the popover's switch redraws.
    private var newCaptureSettingChanges = 0
    /// The crop being adjusted while the crop tool is active, in image pixels: the frame crop, else all of the content.
    /// It's applied as one undo step when the tool is put down, and dropped by Escape.
    var cropDraft: CGRect?
    /// The shape the crop is held to; the last one picked is kept for the next editor.
    var cropAspect: CropAspect = CropAspect(rawValue: UserDefaults.standard.string(forKey: PreferenceKey.editorCropAspect) ?? "") ?? .free {
        didSet { UserDefaults.standard.set(cropAspect.rawValue, forKey: PreferenceKey.editorCropAspect) }
    }
    /// The tool to go back to when the crop tool is put down.
    @ObservationIgnored private var toolBeforeCrop = EditorTool.select
    /// The placed image whose own crop the crop tool is adjusting; `nil` while it adjusts the frame crop.
    private(set) var cropImageID: UUID?
    /// The placed image to crop when the crop tool is next taken up, set by Crop Image.
    @ObservationIgnored private var pendingCropImage: UUID?
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
    private static let showsLayersKey = PreferenceKey.editorShowsLayers
    /// The text or note whose text field is open, with the colour and size picked for it so far; it may not be in the document yet.
    var editingText: Annotation?
    var isDirty: Bool { history.isDirty }
    @ObservationIgnored private var isSaving = false
    /// Set by the canvas: turns the text or note still being typed into an annotation.
    var commitPendingText: (() -> Void)?
    /// The canvas's zoom, where 1 is actual size, for the zoom menu; the canvas view keeps it current.
    /// Zoom is view state, not part of the document, so it isn't undoable.
    var zoom: CGFloat = 1
    private(set) var history: EditHistory
    private var isDraggingStyle = false

    /// `newCaptureStyle` is put on the screenshot as where the document starts, so it's no unsaved change. `windowShadow`
    /// says the image is a window captured with the macOS shadow. `layers` are the live layers and canvas of `version`,
    /// a version saved from this file, which the document starts with instead.
    init(
        fileURL: URL, image: CGImage, scale: CGFloat, windowShadow: Bool = false, style: EditorStyle = Preferences().editorStyle,
        newCaptureStyle: CopiedStyle? = nil, layers: EditorSnapshot? = nil, version: URL? = nil, pristine: URL? = nil
    ) {
        self.fileURL = fileURL
        self.pristine = layers == nil ? nil : pristine
        // A version opened under its own name is one saved over, as a copy would have the original's name.
        canRevert = layers != nil && pristine != nil && version == fileURL
        self.scale = scale
        self.version = layers == nil ? nil : version
        var document = EditorDocument(base: image, background: EditorDocument.defaultBackground(for: ImageFormat(fileExtension: fileURL.pathExtension)))
        document.hasWindowShadow = windowShadow
        if let layers {
            document.restore(layers)
        }
        self.document = document
        history = EditHistory(saved: document.snapshot)
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
        verticalAlignment = style.verticalAlignment
        customColors = style.customColors
        widthIndex = style.widthIndex
        objectStyles = style.objectStyles
        if let newCaptureStyle {
            self.document.pasteStyle(newCaptureStyle, to: [.capture], scale: scale, margin: canvasMargin)
            history.setSaved(self.document.snapshot)
        }
    }

    /// Saves only the value that changed, so another open editor's choices aren't overwritten with this
    /// window's older ones. Select, hand and crop aren't remembered, so the next window starts with the last drawing tool.
    private func rememberStyle(_ change: (inout EditorStyle) -> Void) {
        Preferences.changeEditorStyle(change)
    }

    var selection: Annotation? {
        selectedID.flatMap { id in document.annotations.first { $0.id == id } }
    }

    // MARK: Layers

    /// The annotations frontmost first, as the layers panel lists them.
    var layers: [Annotation] { document.annotations.reversed() }

    var layerRows: [LayerRow] {
        layers.map {
            LayerRow(id: $0.id, name: $0.layerName, symbol: $0.layerSymbol, isHidden: $0.isHidden, isLocked: $0.isLocked, isImage: $0.imageFullRect != nil, isCropped: $0.imageCrop != nil)
        }
    }

    /// The Frame row of the layers panel: there while the image has a crop.
    var frameRow: FrameRow? {
        document.frameCrop.map { _ in FrameRow(isHidden: document.isFrameCropHidden, isSelected: tool == .crop && cropImageID == nil) }
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

    /// Renames layer `id` as one undo step; an empty name goes back to the automatic one.
    func renameLayer(_ id: UUID, to name: String) {
        edit { doc in
            if let index = doc.annotations.firstIndex(where: { $0.id == id }) {
                doc.annotations[index].rename(to: name)
            }
        }
    }

    func duplicateLayers(_ ids: Set<UUID>) {
        let copies = document.annotations.filter { ids.contains($0.id) }
        guard !copies.isEmpty else {
            return
        }
        tool = .select
        var pasted: [UUID] = []
        edit { doc in pasted = copies.map { doc.paste($0, step: pasteStep, margin: canvasMargin) } }
        selectedIDs = Set(pasted)
    }

    func deleteLayers(_ ids: Set<UUID>) {
        var removed: Set<UUID> = []
        edit { removed = $0.deleteLayers(ids, margin: canvasMargin) }
        selectedIDs.subtract(removed)
    }

    /// The toolbar's state, built from the editor's; see `ShotCore.AnnotationPalette`.
    private var palette: ShotCore.AnnotationPalette {
        ShotCore.AnnotationPalette(
            style: nextStyle, editingText: editingText,
            editingTextIsNew: editingText.map { text in !document.annotations.contains { $0.id == text.id } } ?? false,
            selection: selection, tool: tool, scale: scale, imageLength: CGFloat(max(document.base.width, document.base.height)),
            sharedSpotlight: document.spotlightStyle
        )
    }

    /// The style the tool's next annotation gets.
    private var nextStyle: EditorStyle {
        EditorStyle(
            tool: tool, color: color, noteColor: noteColor, highlightColor: highlightColor, fill: fill, widthIndex: widthIndex,
            customColors: customColors, shape: shape, redaction: redaction, redactionAmount: redactionAmount, spotlight: spotlight,
            alignment: alignment, verticalAlignment: verticalAlignment, objectStyles: objectStyles
        )
    }

    /// Takes on what a palette setter changed: the text being typed, the selection as one undo step, which calls with the
    /// same `coalescing` key in a row share, and the next annotation's style. Only what changed is remembered, so two
    /// windows don't overwrite each other's choices.
    private func adopt(_ changed: ShotCore.AnnotationPalette, coalescing key: String? = nil) {
        if changed.editingText != editingText {
            editingText = changed.editingText
        }
        if let restyled = changed.selection, restyled != selection {
            restyleSelection(coalescing: key) { $0 = restyled }
        }
        let next = changed.style
        if next.color != color { color = next.color }
        if next.noteColor != noteColor { noteColor = next.noteColor }
        if next.highlightColor != highlightColor { highlightColor = next.highlightColor }
        if next.fill != fill { fill = next.fill }
        if next.widthIndex != widthIndex { widthIndex = next.widthIndex }
        if next.shape != shape { shape = next.shape }
        if next.redaction != redaction { redaction = next.redaction }
        if next.redactionAmount != redactionAmount { redactionAmount = next.redactionAmount }
        if next.spotlight != spotlight { spotlight = next.spotlight }
        if next.alignment != alignment { alignment = next.alignment }
        if next.verticalAlignment != verticalAlignment { verticalAlignment = next.verticalAlignment }
        for (slot, colour) in next.customColors where customColors[slot] != colour {
            customColors[slot] = colour
            rememberStyle { $0.customColors[slot] = colour }
        }
    }

    /// The colour the palette shows and sets: the text being typed's, else the selection's, else the colour for the tool's next annotation.
    var paletteColor: RGBA {
        get { palette.color }
        set {
            var changed = palette
            changed.setColor(newValue)
            adopt(changed)
        }
    }

    /// The colour for the tool's next annotation: notes and the highlighter keep their own.
    var nextColor: RGBA { palette.nextColor }

    /// True when the toolbar offers a colour and width: the text being typed or the selection takes them, or else the tool does.
    var showsStyle: Bool { palette.showsStyle }

    /// True when the width sets a text size, so the toolbar offers sizes rather than line widths.
    var sizesText: Bool { palette.sizesText }

    /// True when the toolbar offers a fill: a shape is selected, or is the tool.
    var showsFill: Bool { palette.showsFill }

    /// The outline the toolbar shows: the selected shape's, else the next shape's. `nil` when neither is a shape.
    var paletteShape: BoxShape? { palette.shape }

    func setShape(_ newShape: BoxShape) {
        var changed = palette
        changed.setShape(newShape)
        adopt(changed)
    }

    /// How the toolbar shows a redaction hiding: the selected one's, else the next one's. `nil` when neither is one.
    var paletteRedaction: Redaction? { palette.redaction }

    func setRedaction(_ newRedaction: Redaction) {
        var changed = palette
        changed.setRedaction(newRedaction)
        adopt(changed)
    }

    /// How strongly the toolbar shows a redaction hiding: the selected one's, else the next one's.
    var paletteRedactionAmount: CGFloat { palette.redactionAmount }

    /// Sets how strongly the selected redaction, or the next one, hides. Changes during a drag of a style slider are one undo step.
    func setRedactionAmount(_ amount: CGFloat) {
        var changed = palette
        changed.setRedactionAmount(amount)
        adopt(changed, coalescing: isDraggingStyle ? selection.map { "\($0.id)-redaction-amount" } : nil)
    }

    /// The next spotlight's style: the chosen shape and edge, with the effect and strength the image's spotlights already share.
    var nextSpotlightStyle: SpotlightStyle { palette.nextSpotlightStyle }

    /// The spotlight style the toolbar shows: the selected spotlight's, else the next one's. `nil` when neither is one.
    var paletteSpotlight: SpotlightStyle? { palette.spotlight }

    func setSpotlightShape(_ newShape: BoxShape) {
        var changed = palette
        changed.setSpotlightShape(newShape)
        adopt(changed)
    }

    /// Changes during a drag of a style slider are one undo step.
    func setSpotlightSoftEdge(_ softEdge: Double) {
        var changed = palette
        changed.setSpotlightSoftEdge(softEdge)
        adopt(changed, coalescing: isDraggingStyle ? "spotlight-edge" : nil)
    }

    /// Sets the effect and strength of every spotlight in the image, since they share one dim, and of the next one.
    /// Changes during a drag of a style slider are one undo step.
    func setSpotlightLook(effect: SpotlightStyle.Effect, strength: Double) {
        spotlight.effect = effect
        spotlight.strength = strength
        edit(coalescing: isDraggingStyle ? "spotlight-look" : nil) { $0.setSpotlights(effect: effect, strength: strength) }
    }

    /// True when the toolbar's options row has options that aren't the defaults, so Reset has something to do.
    var canResetToolOptions: Bool { palette.canReset }

    /// Puts the toolbar's options back to the defaults of a fresh install: the selected object's, the text being typed's, and
    /// the ones the next object starts with, as one undo step. A spotlight's effect and strength go back for every
    /// spotlight in the image, since they share them.
    func resetToolOptions() {
        let before = palette
        var changed = before
        changed.reset()
        guard changed != before else {
            return
        }
        history.stopCoalescing()
        let restyled = changed.selection != selection ? changed.selection : nil
        let look = changed.sharedSpotlight != before.sharedSpotlight ? changed.sharedSpotlight : nil
        edit { doc in
            if let restyled, let index = doc.annotations.firstIndex(where: { $0.id == restyled.id }), !doc.annotations[index].isLocked {
                doc.annotations[index] = restyled
                doc.grow(toFit: restyled, margin: canvasMargin)
                doc.shrinkPadding(margin: canvasMargin)
            }
            if let look {
                doc.setSpotlights(effect: look.effect, strength: look.strength)
            }
        }
        adopt(changed)
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

    /// Whether the Style popover's target is a window captured with the macOS shadow.
    var targetHasWindowShadow: Bool {
        styleTarget == .capture && document.hasWindowShadow
    }

    /// What the Style popover's tiles draw: the screenshot or placed image itself, or the mark or text.
    var targetThumbnail: StyleThumbnail.Subject? {
        switch styleTarget {
        case .capture:
            return .image(document.base)
        case let .annotation(id):
            guard let annotation = document.annotations.first(where: { $0.id == id }) else {
                return nil
            }
            if case let .image(image, _) = annotation.kind {
                return .image(image.cropped(annotation.imageCrop))
            }
            return .annotation(annotation)
        case nil:
            return nil
        }
    }

    var thumbnailBackground: RGBA? { document.background }

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

    /// Puts the target's shadow, border and corners back to how a new one of its kind starts, as one undo step, and
    /// remembers that style for the next one. The screenshot's "use for new captures" setting stays as it is.
    func resetTargetStyle() {
        guard let styleTarget, let kind = targetStyleKind else {
            return
        }
        stylePreview = nil
        let style = kind.defaultStyle.scaled(by: scale)
        let radius = kind.defaultCornerRadius * scale
        edit {
            $0.setStyle(style, of: styleTarget, margin: canvasMargin)
            if kind.takesCorners {
                $0.setCornerRadius(radius, of: styleTarget)
            }
        }
        if kind != .capture {
            objectStyles[kind] = kind.defaultStyle
            rememberStyle { $0.objectStyles[kind] = kind.defaultStyle }
        }
    }

    /// Changes during a drag of a style slider are one undo step.
    func setShadowElevation(_ points: CGFloat) {
        restyleTarget(coalescing: "shadow") { $0.shadow?.elevation = points * scale }
    }

    /// Changes during a drag of a style slider are one undo step.
    func setShadowOpacity(_ opacity: CGFloat) {
        restyleTarget(coalescing: "shadow") { $0.shadow?.opacity = opacity }
    }

    /// The colour a border picked from the custom colour editor had last, which its rainbow swatch applies again; `nil`
    /// until one is picked, so the swatch doesn't offer white, which the palette has.
    private(set) var lastBorderColor: RGBA?

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

    /// Whether new captures get this screenshot's style: the setting is on, and the style it saved is this one.
    /// Read from Settings each time, so another window's change shows here too.
    var usesStyleForNewCaptures: Bool {
        _ = newCaptureSettingChanges
        return document.captureHas(Preferences().newCaptureStyle, scale: scale)
    }

    /// Whether new captures get a saved style that isn't this screenshot's.
    var newCapturesHaveOtherStyle: Bool {
        _ = newCaptureSettingChanges
        return Preferences().newCaptureStyle != nil && !usesStyleForNewCaptures
    }

    /// Saves the screenshot's style for new captures to open and copy with, or turns that off.
    func setUsesStyleForNewCaptures(_ on: Bool) {
        Preferences.styleNewCaptures(with: on ? document.copyStyle(of: .capture, scale: scale) : nil)
        newCaptureSettingChanges += 1
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
        StyleClipboard.copied = copied
        Toast.show("Copied style")
    }

    var canPasteStyle: Bool { StyleClipboard.copied != nil }

    /// Puts the copied style on every selected annotation that takes one, or on the screenshot when nothing is selected,
    /// as one undo step. Each takes only what it can have.
    func pasteStyle() {
        guard let copied = StyleClipboard.copied, editingText == nil else {
            return
        }
        let targets: [StyleTarget] = selectedIDs.isEmpty ? [.capture] : document.annotations.filter { selectedIDs.contains($0.id) }.map { .annotation($0.id) }
        edit { $0.pasteStyle(copied, to: targets, scale: scale, margin: canvasMargin) }
    }

    /// Puts the copied style on the screenshot and every placed image as one undo step.
    func applyStyleToAllImages() {
        guard let copied = StyleClipboard.copied, editingText == nil else {
            return
        }
        edit { $0.pasteStyle(copied, to: $0.imageStyleTargets, scale: scale, margin: canvasMargin) }
    }

    /// Call as a drag of a style slider starts and ends, so each drag is one undo step.
    func setDraggingStyle(_ dragging: Bool) {
        isDraggingStyle = dragging
        history.stopCoalescing()
    }

    /// The alignment the toolbar shows: the text being typed's, else the selection's, else the next text's or note's.
    /// `nil` when none of them is text or a note.
    var paletteAlignment: TextAlign? { palette.alignment }

    func setAlignment(_ newAlignment: TextAlign) {
        var changed = palette
        changed.setAlignment(newAlignment)
        adopt(changed)
    }

    /// Where the toolbar shows the note's text sitting: the one being typed's, else the selection's, else the next note's.
    /// `nil` when none of them is a note.
    var paletteVerticalAlignment: VerticalTextAlign? { palette.verticalAlignment }

    func setVerticalAlignment(_ newAlignment: VerticalTextAlign) {
        var changed = palette
        changed.setVerticalAlignment(newAlignment)
        adopt(changed)
    }

    /// The fill the toolbar shows and sets, `nil` for none: the selection's, else the fill for the next shape.
    var paletteFill: RGBA? {
        get { palette.fill }
        set {
            var changed = palette
            changed.setFill(newValue)
            adopt(changed)
        }
    }

    /// Call as the colour editor opens, so its run of picks doesn't join the last one's undo step.
    func beginColorPick() {
        history.stopCoalescing()
    }

    /// Sets the border colour, or the fill, to one picked from the colour panel, which reports every
    /// change as the user drags. It's one undo step, and becomes the palette's last custom colour.
    func pickCustom(_ colour: RGBA, forFill: Bool) {
        var changed = palette
        changed.pickCustom(colour, forFill: forFill)
        adopt(changed, coalescing: selection.map { "\($0.id)-\(forFill)" })
    }

    /// The border or fill palette's last custom colour.
    func lastCustom(forFill: Bool) -> RGBA? {
        palette.lastCustom(forFill: forFill)
    }

    /// The width the toolbar shows and sets: the text being typed's, else the selection's nearest, else the width for the
    /// next annotation.
    var lineWidthIndex: Int {
        get { palette.lineWidthIndex }
        set {
            var changed = palette
            changed.setLineWidthIndex(newValue)
            adopt(changed)
        }
    }

    var lineWidth: CGFloat { Self.baseWidths[widthIndex] * scale }
    var fontSize: CGFloat { lineWidth * 6 }
    /// What the toolbar gives the annotation the canvas draws next.
    var draftStyle: AnnotationDraft.Style {
        AnnotationDraft.Style(
            color: nextColor, fill: fill, noteColor: noteColor, lineWidth: lineWidth, shape: shape,
            redaction: redaction, redactionAmount: redactionAmount, spotlight: nextSpotlightStyle, alignment: alignment,
            verticalAlignment: verticalAlignment
        )
    }
    /// Space kept between an annotation and a canvas edge that grew to hold it.
    var canvasMargin: CGFloat { 16 * scale }
    /// How far down and right a paste or duplicate lands from the original.
    var pasteStep: CGFloat { 10 * scale }
    var isJPEG: Bool { ImageFormat(fileExtension: fileURL.pathExtension) == .jpeg }

    /// Call as a move or resize on the canvas starts. Its changes, made with `apply`, undo as one step once it ends.
    func beginGesture() {
        history.beginGesture(document)
    }

    /// Makes one change of the gesture in progress; outside a gesture it's an undo step of its own.
    func apply(_ change: (inout EditorDocument) -> Void) {
        history.apply(&document, change)
    }

    /// Records the gesture in progress as one undo step, or none if it left the document as it was.
    func endGesture() {
        history.endGesture(document)
    }

    // MARK: Crop

    private func beginCrop(from previous: EditorTool, image: UUID?) {
        toolBeforeCrop = CropEditing.toolBefore(taking: previous)
        let annotation = image.flatMap { image in document.annotations.first { $0.id == image } }
        cropImageID = annotation?.id
        cropDraft = CropEditing.startingDraft(imageBounds: annotation?.bounds, frameCrop: document.frameCrop, contentRect: document.contentRect)
    }

    /// The selection, when it's a placed image that can be cropped.
    private var croppableSelection: UUID? {
        selection.flatMap { $0.imageFullRect != nil && !$0.isLocked ? $0.id : nil }
    }

    /// Where the image being cropped would be drawn whole, which its crop is kept within; `nil` while cropping the frame.
    var cropImageFullRect: CGRect? {
        cropImageID.flatMap { id in document.annotations.first { $0.id == id }?.imageFullRect }
    }

    /// Takes up the crop tool on the placed image with `id`, as double-clicking it, Crop Image or its Layers badge does.
    func cropImage(_ id: UUID) {
        guard let annotation = document.annotations.first(where: { $0.id == id }), annotation.imageFullRect != nil, !annotation.isLocked else {
            return
        }
        if tool == .crop {
            cancelCrop()
        }
        pendingCropImage = id
        tool = .crop
    }

    /// Shows all of the placed image with `id` again, as one undoable step.
    func resetImageCrop(_ id: UUID) {
        if cropImageID == id {
            cancelCrop()
        }
        edit { $0.resetImageCrop(id, margin: canvasMargin) }
    }

    /// Applies the crop being adjusted as one undoable step; it's none if the crop is as it was.
    private func finishCrop() {
        let image = cropImageID
        cropImageID = nil
        guard let draft = cropDraft else {
            reselect(image)
            return
        }
        cropDraft = nil
        let target = image.map { image in (id: image, bounds: document.annotations.first { $0.id == image }?.bounds) }
        switch CropEditing.outcome(draft: draft, image: target, frameCrop: document.frameCrop, contentRect: document.contentRect, isFrameCropHidden: document.isFrameCropHidden) {
        case .nothing:
            break
        case let .cropImage(id, visible):
            edit { $0.cropImage(id, to: visible, margin: canvasMargin) }
        case let .cropFrame(rect):
            edit { $0.crop(to: rect) }
        }
        reselect(image)
    }

    /// Picks the image just cropped again once the select tool is back, so its handles show.
    private func reselect(_ image: UUID?) {
        if let image, tool == .select {
            selectedID = image
        }
    }

    /// Puts the crop tool down, applying the crop, as Return does.
    func applyCrop() {
        tool = toolBeforeCrop
    }

    /// Copy and Save take the crop as it's drawn, so it's in what they produce.
    private func applyCropIfCropping() {
        if tool == .crop {
            applyCrop()
        }
    }

    /// Puts the crop tool down, dropping what was changed, as Escape does.
    func cancelCrop() {
        cropDraft = nil
        tool = toolBeforeCrop
    }

    /// Picks the shape the crop is held to, and fits the largest crop of that shape inside the current one.
    func chooseCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        if let draft = cropDraft {
            cropDraft = CropEditing.draft(draft, holding: aspect)
        }
    }

    /// Makes the crop all of the content again; while the crop tool is active that applies when it's put down.
    func resetCrop() {
        if cropDraft != nil {
            cropDraft = CropEditing.resetDraft(fullRect: cropImageFullRect, contentRect: document.contentRect)
        } else {
            edit { $0.resetCrop() }
        }
    }

    /// Whether there's a crop to take off, which Reset offers.
    var canResetCrop: Bool {
        CropEditing.canReset(draft: cropDraft, fullRect: cropImageFullRect, contentRect: document.contentRect, hasFrameCrop: document.frameCrop != nil)
    }

    /// Shows the uncropped image, and leaves the crop out of Copy and Save, or puts it back.
    func setFrameCropHidden(_ hidden: Bool) {
        edit { $0.isFrameCropHidden = hidden }
    }

    /// Removes the frame crop from the Frame row, as one undoable step.
    func deleteFrame() {
        cropDraft = nil
        if tool == .crop {
            tool = toolBeforeCrop
        }
        edit { $0.resetCrop() }
    }

    func undo() {
        guard tool != .crop else {
            cancelCrop()
            return
        }
        if history.undo(&document) {
            keepSelectionThatRemains()
        }
    }

    func redo() {
        guard tool != .crop else {
            cancelCrop()
            return
        }
        if history.redo(&document) {
            keepSelectionThatRemains()
        }
    }

    /// Keeps the layers picked that are still in the document after an undo or redo, so the toolbar shows their style as
    /// it now is.
    private func keepSelectionThatRemains() {
        selectedIDs.formIntersection(document.annotations.map(\.id))
    }

    /// Adds `annotation` as one undoable step, growing the canvas if it reaches past the edge, and selects it
    /// so the toolbar can fix its style until the next one is drawn. A mark or text starts with the last style given to its kind.
    func add(_ annotation: Annotation) {
        var annotation = annotation
        if let kind = annotation.styleKind, annotation.style.isEmpty {
            annotation.style = startingStyle(for: kind)
        }
        edit { doc in
            doc.annotations.append(annotation)
            doc.grow(toFit: annotation, margin: canvasMargin)
        }
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

    /// The background picked last from the custom colour editor, which its rainbow swatch applies again; `nil` until one
    /// is picked.
    private(set) var lastBackgroundColor: RGBA?

    /// Sets the background to one picked from the colour editor, which reports every change as the user drags. Each
    /// opening of the editor is one undo step. A JPEG's is opaque, since JPEG has no alpha to keep it see-through.
    func pickBackground(_ color: RGBA) {
        var color = color
        if isJPEG {
            color.a = 1
        }
        lastBackgroundColor = color
        edit(coalescing: "background") { $0.background = color }
    }

    /// Applies `change` as one undoable step, or does nothing if it leaves the document as it was.
    /// Calls with the same `key` in a row amend that step instead of adding another.
    private func edit(coalescing key: String? = nil, _ change: (inout EditorDocument) -> Void) {
        history.edit(&document, coalescing: key, change)
    }

    /// Moves the selection by one pixel, or ten when `large`, growing the canvas if it reaches past the edge.
    /// A `repeated` press (the key held down) joins the undo step of the press before it.
    func nudgeSelection(_ direction: NudgeDirection, large: Bool, repeated: Bool) {
        guard let selectedID = selection?.id, selection?.isLocked != true else {
            return
        }
        if !repeated {
            history.stopCoalescing()
        }
        edit(coalescing: "\(selectedID)-nudge") { $0.move(selectedID, by: direction.offset(large: large), margin: canvasMargin) }
    }

    /// Adds an offset copy of `annotation` as one undoable step and selects it.
    private func insertCopy(of annotation: Annotation) {
        var id: UUID?
        edit { id = $0.paste(annotation, step: pasteStep, margin: canvasMargin) }
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
            Toast.error("Couldn't paste: \(error.localizedDescription)")
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
            Toast.error("Couldn't read the image")
            return
        }
        tool = .select
        let style = startingStyle(for: .image)
        var added: UUID?
        edit { doc in
            for (index, (image, imageScale)) in decoded.enumerated() {
                let center = point.map { CGPoint(x: $0.x + pasteStep * CGFloat(index), y: $0.y + pasteStep * CGFloat(index)) }
                let id = doc.addImage(image, scale: imageScale, documentScale: scale, centeredAt: center, margin: canvasMargin)
                // It starts with the last style given to an image, but for an outline it has no see-through pixels for.
                if !style.isEmpty {
                    doc.setStyle(style, of: .annotation(id), margin: canvasMargin)
                }
                added = id
            }
        }
        selectedID = added
    }

    /// Places the images in the files at `urls` beside the canvas, as pasting them does.
    func addImageFiles(_ urls: [URL]) {
        addImages(urls.compactMap { try? Data(contentsOf: $0) }, at: nil)
    }

    func deleteSelection() {
        deleteLayers(selectedIDs)
    }

    /// The flattened image as a PNG, for the clipboard.
    private func renderedPNG() async -> Data? {
        let document = document, scale = scale
        return await Task.detached {
            try? VersionWriter.render(document, scale: scale, as: .png).file
        }.value
    }

    /// Copies the selected annotation. Returns false if nothing is selected.
    func copySelection() -> Bool {
        guard let selection else {
            return false
        }
        Task {
            do {
                try await Clipboard.copy(annotation: selection)
                Toast.show("Copied annotation")
            } catch {
                Toast.error("Couldn't copy: \(error.localizedDescription)")
            }
        }
        return true
    }

    /// Copies the flattened image.
    func copy() async {
        commitPendingText?()
        applyCropIfCropping()
        guard let png = await renderedPNG() else {
            Toast.error("Couldn't copy the image")
            return
        }
        Clipboard.copy(png: png)
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
        applyCropIfCropping()
        let snapshot = document.snapshot
        let prefs = Preferences()
        let overwriting = prefs.editorSavesOverOriginal && prefs.isOwnCapture(version ?? fileURL)
        let document = document, scale = scale, target = overwriting ? version ?? fileURL : fileURL, pristine = pristine
        let saved = await Task.detached {
            Result { () throws(VersionWriter.Failure) in
                try VersionWriter.saveImage(document, of: target, pristine: pristine, overwriting: overwriting, scale: scale, projects: .app)
            }
        }.value
        switch saved {
        case let .success(version):
            Clipboard.copy(png: version.png)
            let overwrote = version.url == target
            self.version = version.url
            self.pristine = version.original
            canRevert = overwrote
            history.didSave(snapshot, document: self.document)
            let note = TemporaryCaptures.toastNote(for: version.url)
            Toast.show(overwrote ? "Saved over \(version.url.lastPathComponent) and copied.\(note)" : "Saved as \(version.url.lastPathComponent) and copied.\(note)", duration: .seconds(3))
            return true
        case .failure(.draw), .failure(.encode):
            Toast.error("Couldn't save the image")
            return false
        case let .failure(.write(error)):
            Toast.error("Couldn't save: \(error.localizedDescription)")
            return false
        }
    }
}
