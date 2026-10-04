import AppKit
import ShotCore

final class EditorCanvasView: NSView, NSTextFieldDelegate {
    private let model: EditorModel
    private var draft: Annotation?
    private var cropDraft: CGRect?
    private var dragStart: CGPoint?
    private var lastPoint: CGPoint?
    private var movedSinceMouseDown = false
    private var textField: NSTextField?
    private var textOrigin: CGPoint?
    /// The note whose text field is open; it may not be in the document yet.
    private var editingNote: Annotation?
    /// The text annotation whose text field is open, hidden while it's edited.
    private var editingTextID: UUID?
    private var resizeHandle: AnnotationHandle?
    /// The selection as it was when the resize began; every drag resizes from it.
    private var resizeStart: Annotation?
    /// The font size of the text being typed or edited, in image pixels.
    private var textFontSize: CGFloat?
    /// The zoom and scroll position, or nil to fit the canvas to the view as it resizes.
    /// They're view state, not part of the document, so they aren't undoable.
    private var zoomedViewport: Viewport?
    /// True while Space is held, when a drag scrolls instead of using the tool.
    private var spaceHeld = false
    /// The last view point of a Space-drag scroll.
    private var panPoint: CGPoint?

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        observe()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func observe() {
        withObservationTracking {
            _ = model.document.annotations
            _ = model.document.canvasRect
            _ = model.document.background
            _ = model.selectedID
            _ = model.tool
        } onChange: { [weak self] in
            Task { @MainActor in
                // A fitted canvas rescales as it grows or is cropped.
                self?.viewportDidChange()
                self?.observe()
            }
        }
    }

    override func layout() {
        super.layout()
        viewportDidChange()
    }

    // MARK: Geometry

    /// The whole canvas, no larger than actual size.
    private var fitViewport: Viewport {
        .fit(model.document.canvasRect, in: bounds.size, maxScale: Viewport.scale(forZoom: 1, pixelsPerPoint: model.scale))
    }

    /// Clamped on every read, so a crop or a window resize never leaves the canvas scrolled away.
    private var viewport: Viewport {
        zoomedViewport?.clamped(to: model.document.canvasRect, in: bounds.size) ?? fitViewport
    }

    /// View points per image pixel.
    private var viewScale: CGFloat { viewport.scale }

    /// The canvas, in view points.
    private var imageRect: CGRect { viewport.viewRect(model.document.canvasRect) }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        viewport.imagePoint(convert(event.locationInWindow, from: nil))
    }

    private func viewRect(_ imageRect: CGRect) -> CGRect {
        viewport.viewRect(imageRect)
    }

    private func clampedToCanvas(_ point: CGPoint) -> CGPoint {
        let canvas = model.document.canvasRect
        return CGPoint(x: min(max(point.x, canvas.minX), canvas.maxX), y: min(max(point.y, canvas.minY), canvas.maxY))
    }

    // MARK: Drawing

    /// Marks transparent padding, as image editors do.
    private static let checkerboard = NSColor(patternImage: NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        NSColor(white: 0.85, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        NSRect(x: 8, y: 8, width: 8, height: 8).fill()
        return true
    })

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }
        var doc = model.document
        // The note being edited is drawn as blank paper under its text field instead.
        if let editingNote {
            doc.annotations.removeAll { $0.id == editingNote.id }
        }
        if let editingTextID {
            doc.annotations.removeAll { $0.id == editingTextID }
        }
        // A spotlight's dim is drawn with the document's, so its draft joins the document.
        if let draft, case .spotlight = draft.kind {
            doc.annotations.append(draft)
        }
        let rect = imageRect
        let ink = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1)
        ink.setFill()
        rect.offsetBy(dx: 5, dy: 5).fill()
        if doc.background == nil, doc.hasPadding {
            let padding = NSBezierPath(rect: rect)
            let image = doc.fullRect.intersection(doc.canvasRect)
            if !image.isNull {
                padding.append(NSBezierPath(rect: viewRect(image)))
            }
            padding.windingRule = .evenOdd
            Self.checkerboard.setFill()
            padding.fill()
        }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: viewScale, y: -viewScale)
        // Zoomed in to two or more screen pixels per image pixel, show the pixels themselves rather than smoothing them.
        ctx.interpolationQuality = viewScale * (window?.backingScaleFactor ?? 2) >= 2 ? .none : .high
        AnnotationRenderer.render(doc, into: ctx)
        ctx.restoreGState()
        // The draft isn't clipped to the canvas, so it shows where the canvas will grow to on release.
        for unclipped in [draft, editingPaper].compactMap({ $0 }) {
            ctx.saveGState()
            ctx.translateBy(x: rect.minX, y: rect.minY)
            ctx.scaleBy(x: viewScale, y: viewScale)
            ctx.translateBy(x: -doc.canvasRect.minX, y: -doc.canvasRect.minY)
            AnnotationRenderer.draw(unclipped, base: doc.base, in: ctx)
            ctx.restoreGState()
        }
        ink.setStroke()
        let frame = NSBezierPath(rect: rect.insetBy(dx: -1.25, dy: -1.25))
        frame.lineWidth = 2.5
        frame.stroke()

        if let selected = model.selection, selected.id != editingTextID {
            let outline = NSBezierPath(rect: viewRect(selected.bounds.insetBy(dx: -selected.lineWidth, dy: -selected.lineWidth)))
            outline.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
            if editingNote == nil {
                for handle in selected.handles {
                    let center = viewRect(CGRect(origin: handle.point, size: .zero)).origin
                    let square = NSBezierPath(rect: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                    NSColor.white.setFill()
                    square.fill()
                    square.stroke()
                }
            }
        }
        if let cropDraft {
            let crop = viewRect(cropDraft)
            let dim = NSBezierPath(rect: rect)
            dim.append(NSBezierPath(rect: crop))
            dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.5).setFill()
            dim.fill()
            NSColor.white.setStroke()
            NSBezierPath(rect: crop).stroke()
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if textField != nil {
            commitText()
            return
        }
        if spaceHeld {
            panPoint = convert(event.locationInWindow, from: nil)
            NSCursor.closedHand.set()
            return
        }
        let point = imagePoint(event)
        dragStart = point
        lastPoint = point
        movedSinceMouseDown = false
        switch model.tool {
        case .select:
            let tolerance = 6 / viewScale
            let hit = model.document.annotations.topmostIndex(at: point, tolerance: tolerance).map { model.document.annotations[$0] }
            // The toolbar restyles the selection, which the open editor wouldn't show, so editing
            // deselects; closing the editor selects it again.
            if event.clickCount == 2, let hit, case .note = hit.kind {
                model.selectedID = nil
                beginNote(hit)
            } else if event.clickCount == 2, let hit, case let .text(_, origin, _) = hit.kind {
                model.selectedID = nil
                beginText(at: origin, editing: hit)
            } else if let selected = model.selection, let handle = selected.handle(at: point, tolerance: tolerance) {
                resizeHandle = handle
                resizeStart = selected
            } else if let hit {
                model.selectedID = hit.id
            } else {
                model.selectedID = nil
            }
        case .note:
            // Clicking a note with the note tool edits it rather than stacking a new one on top.
            if let index = model.document.annotations.topmostIndex(at: point, tolerance: 6 / viewScale), case .note = model.document.annotations[index].kind {
                beginNote(model.document.annotations[index])
            } else {
                model.selectedID = nil
            }
        case .counter:
            model.add(Annotation(kind: .counter(model.document.annotations.nextCounterNumber, center: point), color: model.color, lineWidth: model.lineWidth))
        case .text:
            beginText(at: point)
        default:
            model.selectedID = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let panPoint {
            let point = convert(event.locationInWindow, from: nil)
            pan(by: CGVector(dx: point.x - panPoint.x, dy: point.y - panPoint.y))
            self.panPoint = point
            return
        }
        guard let start = dragStart, let last = lastPoint else {
            return
        }
        let point = imagePoint(event)
        defer { lastPoint = point }
        let rect = Geometry.normalized(from: start, to: point)
        let kind: Annotation.Kind
        switch model.tool {
        case .select:
            guard let id = model.selectedID, let index = model.document.annotations.firstIndex(where: { $0.id == id }) else {
                return
            }
            if !movedSinceMouseDown {
                model.recordUndo()
                movedSinceMouseDown = true
            }
            if let resizeHandle, var resized = resizeStart {
                resized.resize(resizeHandle, to: point)
                model.document.annotations[index] = resized
            } else {
                model.document.annotations[index].offset(by: CGVector(dx: point.x - last.x, dy: point.y - last.y))
            }
            return
        case .crop:
            cropDraft = Geometry.normalized(from: clampedToCanvas(start), to: clampedToCanvas(point))
            needsDisplay = true
            return
        case .counter, .text:
            return
        case .arrow:
            kind = .arrow(from: start, to: point)
        case .line:
            kind = .line(from: start, to: point)
        case .rect:
            kind = .rect(rect)
        case .ellipse:
            kind = .ellipse(rect)
        case .highlight:
            kind = .highlight(rect)
        case .pixelate:
            kind = .pixelate(rect)
        case .blur:
            kind = .blur(rect)
        case .spotlight:
            kind = .spotlight(rect)
        case .pen:
            let points: [CGPoint]
            if let draft, case let .freehand(drawn) = draft.kind {
                points = drawn
            } else {
                points = [start]
            }
            // Points closer than a view point apart add nothing the curve can show.
            kind = .freehand(Freehand.adding(point, to: points, minDistance: 1 / viewScale))
        case .note:
            draft = newNote(id: draft?.id ?? UUID(), from: start, to: point)
            needsDisplay = true
            return
        }
        draft = Annotation(id: draft?.id ?? UUID(), kind: kind, color: model.color, lineWidth: model.lineWidth)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if panPoint != nil {
            panPoint = nil
            (spaceHeld ? NSCursor.openHand : NSCursor.arrow).set()
            return
        }
        defer {
            draft = nil
            cropDraft = nil
            dragStart = nil
            resizeHandle = nil
            resizeStart = nil
            needsDisplay = true
        }
        if model.tool == .note, let start = dragStart {
            beginNote(newNote(id: draft?.id ?? UUID(), from: start, to: imagePoint(event)))
            return
        }
        if let cropDraft, cropDraft.width >= 4, cropDraft.height >= 4 {
            model.recordUndo()
            model.document.crop(to: cropDraft)
        }
        // A spotlight with no area would light nothing, so it isn't added.
        if let draft, case .spotlight = draft.kind, draft.bounds.isEmpty {
            return
        }
        if let draft, draft.bounds.width + draft.bounds.height >= 4 {
            model.add(draft)
        }
        // The move or resize recorded its undo step when it began, so growing joins that step.
        if model.tool == .select, movedSinceMouseDown, let id = model.selectedID, let moved = model.document.annotations.first(where: { $0.id == id }) {
            model.document.grow(toFit: moved, margin: model.canvasMargin)
        }
    }

    // MARK: Keyboard

    private static let nudgeDirections: [UInt16: NudgeDirection] = [123: .left, 124: .right, 125: .down, 126: .up]

    override func keyDown(with event: NSEvent) {
        // Space scrolls while held; a drag already under way keeps using the tool.
        if event.keyCode == 49 {
            if !spaceHeld, dragStart == nil {
                spaceHeld = true
                NSCursor.openHand.set()
            }
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            model.deleteSelection()
            return
        }
        if event.keyCode == 53 {
            model.selectedID = nil
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if modifiers.isEmpty, model.selectedID != nil, let direction = Self.nudgeDirections[event.keyCode] {
            model.nudgeSelection(direction, large: event.modifierFlags.contains(.shift), repeated: event.isARepeat)
            return
        }
        if modifiers.isEmpty, let character = event.charactersIgnoringModifiers?.lowercased().first, let tool = EditorTool.allCases.first(where: { $0.key == character }) {
            model.tool = tool
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49 else {
            super.keyUp(with: event)
            return
        }
        spaceHeld = false
        if panPoint == nil {
            NSCursor.arrow.set()
        }
    }

    // Once a text field takes the keyboard, Space's release never reaches this view.
    override func resignFirstResponder() -> Bool {
        if spaceHeld {
            spaceHeld = false
            NSCursor.arrow.set()
        }
        return super.resignFirstResponder()
    }

    // MARK: Zoom

    func zoomIn() {
        zoom(to: Viewport.zoom(after: currentZoom), about: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    func zoomOut() {
        zoom(to: Viewport.zoom(before: currentZoom), about: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    func zoomToActualSize() {
        zoom(to: 1, about: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    func zoomToFit() {
        zoomedViewport = nil
        viewportDidChange()
    }

    private var currentZoom: CGFloat { viewport.zoom(pixelsPerPoint: model.scale) }

    private func zoom(to zoom: CGFloat, about point: CGPoint) {
        zoomedViewport = viewport.zoomed(to: Viewport.scale(forZoom: zoom, pixelsPerPoint: model.scale), about: point).clamped(to: model.document.canvasRect, in: bounds.size)
        viewportDidChange()
    }

    /// A fitted canvas is all on screen, so it has nowhere to scroll.
    private func pan(by offset: CGVector) {
        guard zoomedViewport != nil else {
            return
        }
        zoomedViewport = viewport.panned(by: offset).clamped(to: model.document.canvasRect, in: bounds.size)
        viewportDidChange()
    }

    override func magnify(with event: NSEvent) {
        let fit = fitViewport.zoom(pixelsPerPoint: model.scale)
        zoom(to: Viewport.clampedZoom(currentZoom * (1 + event.magnification), fit: fit), about: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        guard zoomedViewport != nil else {
            super.scrollWheel(with: event)
            return
        }
        // A mouse wheel counts lines rather than points. The deltas already follow the natural scrolling setting.
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        pan(by: CGVector(dx: event.scrollingDeltaX * step, dy: event.scrollingDeltaY * step))
    }

    /// Shows the new zoom in the toolbar and keeps an open text field over its text.
    private func viewportDidChange() {
        let zoom = currentZoom
        if model.zoom != zoom {
            model.zoom = zoom
        }
        layoutTextField()
        needsDisplay = true
    }

    // MARK: Text

    /// Opens a text field at `point` for new text, or over `existing` text to edit it.
    private func beginText(at point: CGPoint, editing existing: Annotation? = nil) {
        var string = "", rgba = model.color, fontSize = model.fontSize
        if let existing, case let .text(text, _, size) = existing.kind {
            string = text
            rgba = existing.color
            fontSize = size
            editingTextID = existing.id
        }
        // A double-click that wobbles mustn't drag the text being edited.
        dragStart = nil
        textOrigin = point
        textFontSize = fontSize
        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.6)
        field.focusRingType = .none
        field.textColor = NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: 1)
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldAction)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        layoutTextField()
    }

    /// Keeps the open text field over its text, at its size, as the zoom, scroll or window changes.
    private func layoutTextField() {
        if editingNote != nil {
            layoutNoteField()
            return
        }
        guard let field = textField, let textOrigin, let textFontSize else {
            return
        }
        let size = textFontSize * viewScale
        if field.font?.pointSize != size {
            field.font = .boldSystemFont(ofSize: size)
        }
        let origin = viewRect(CGRect(origin: textOrigin, size: .zero)).origin
        if field.stringValue.isEmpty {
            field.frame = CGRect(x: origin.x, y: origin.y, width: 240, height: size * 1.4)
        } else {
            field.frame.origin = origin
            fitTextField(field)
        }
    }

    private func fitTextField(_ field: NSTextField) {
        field.sizeToFit()
        field.frame.size.width = max(240, field.frame.width + 20)
    }

    @objc private func textFieldAction() {
        commitText()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            removeTextField()
            return true
        }
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = textField else {
            return
        }
        if editingNote != nil {
            layoutNoteField()
            return
        }
        fitTextField(field)
    }

    var isEditingText: Bool { textField != nil }

    private func commitText() {
        if let note = editingNote, let field = textField {
            let string = field.stringValue
            removeTextField()
            commitNote(note, text: string)
            return
        }
        guard let field = textField, let origin = textOrigin else {
            return
        }
        let string = field.stringValue
        let editedID = editingTextID
        removeTextField()
        if let editedID {
            model.setText(editedID, to: string)
            return
        }
        guard !string.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        model.add(Annotation(kind: .text(string, origin: origin, fontSize: model.fontSize), color: model.color, lineWidth: model.lineWidth))
    }

    // MARK: Notes

    private func newNote(id: UUID, from start: CGPoint, to end: CGPoint) -> Annotation {
        var note = Annotation(id: id, kind: .note("", rect: .zero), color: model.noteColor, lineWidth: model.lineWidth)
        note.kind = .note("", rect: NoteLayout.placementRect(from: start, to: end, fontSize: note.noteFontSize))
        return note
    }

    /// The note being edited, with the text typed so far.
    private var editedNote: Annotation? {
        guard var note = editingNote, let field = textField else {
            return nil
        }
        note.setText(field.stringValue)
        return note
    }

    /// Blank paper the size the note will be, under its text field.
    private var editingPaper: Annotation? {
        guard let note = editedNote, let frame = note.noteLayout?.frame else {
            return nil
        }
        return Annotation(id: note.id, kind: .note("", rect: frame), color: note.color, lineWidth: note.lineWidth)
    }

    /// Opens a text field over `note`, which is either new or already in the document.
    private func beginNote(_ note: Annotation) {
        guard case let .note(string, _) = note.kind, let layout = note.noteLayout else {
            return
        }
        dragStart = nil
        editingNote = note
        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.placeholderString = "Note"
        let ink = layout.ink
        field.textColor = NSColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: 1)
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldAction)
        addSubview(field)
        textField = field
        layoutNoteField()
        window?.makeFirstResponder(field)
    }

    /// Fits the text field to the note's text area as the text grows.
    private func layoutNoteField() {
        guard let field = textField, let layout = editedNote?.noteLayout else {
            return
        }
        // The zoom changes with the window size and the zoom commands, so the font follows it here.
        let size = layout.fontSize * viewScale
        if field.font?.pointSize != size {
            field.font = .systemFont(ofSize: size)
        }
        // A borderless field insets its text 2 pt on each side.
        field.frame = viewRect(layout.textRect).insetBy(dx: -2, dy: 0)
        needsDisplay = true
    }

    private func commitNote(_ note: Annotation, text string: String) {
        if model.document.annotations.contains(where: { $0.id == note.id }) {
            model.setText(note.id, to: string)
        } else if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var placed = note
            placed.setText(string)
            model.add(placed)
        }
    }

    private func removeTextField() {
        let field = textField
        let editedID = editingNote?.id ?? editingTextID
        textField = nil
        textOrigin = nil
        textFontSize = nil
        editingNote = nil
        editingTextID = nil
        needsDisplay = true
        field?.delegate = nil
        field?.removeFromSuperview()
        window?.makeFirstResponder(self)
        if model.tool == .select, let editedID, model.document.annotations.contains(where: { $0.id == editedID }) {
            model.selectedID = editedID
        }
    }
}
