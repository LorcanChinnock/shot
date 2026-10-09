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
    /// The text or note whose text field is open, hidden while it's edited; it may not be in the document yet.
    /// The model holds it so the toolbar can recolour and resize it.
    private var editingText: Annotation? {
        get { model.editingText }
        set { model.editingText = newValue }
    }
    private var resizeHandle: AnnotationHandle?
    /// The selection as it was when the resize began; every drag resizes from it.
    private var resizeStart: Annotation?
    /// The zoom and scroll position, or nil to fit the canvas to the view as it resizes.
    /// They're view state, not part of the document, so they aren't undoable.
    private var zoomedViewport: Viewport?
    /// True while Space is held, when a drag scrolls instead of using the tool.
    private var spaceHeld = false
    /// The last view point of a scroll by dragging: with Space held, the hand tool or the middle button.
    private var panPoint: CGPoint?

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes([NSPasteboard.PasteboardType.fileURL] + NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) })
        model.commitPendingText = { [weak self] in self?.commitText() }
        observe()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { textField == nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func observe() {
        withObservationTracking {
            _ = model.document.annotations
            _ = model.document.canvasRect
            _ = model.document.background
            _ = model.stylePreview
            _ = model.selectedIDs
            _ = model.tool
            _ = model.editingText
        } onChange: { [weak self] in
            Task { @MainActor in
                // A fitted canvas rescales as it grows or is cropped.
                self?.viewportDidChange()
                if let self {
                    self.window?.invalidateCursorRects(for: self)
                }
                self?.observe()
            }
        }
    }

    override func layout() {
        super.layout()
        viewportDidChange()
    }

    // MARK: Geometry

    /// The canvas as it will be once the draft or note being typed is committed, so it grows and shrinks as they do,
    /// and as a style previewed in the Style popover would make it.
    private var canvasRect: CGRect {
        var doc = model.previewDocument
        for pending in [draft, editingPaper].compactMap({ $0 }) {
            doc.grow(toFit: pending, margin: model.canvasMargin)
        }
        return doc.canvasRect
    }

    /// The whole canvas, no larger than actual size.
    private var fitViewport: Viewport {
        .fit(canvasRect, in: bounds.size, maxScale: Viewport.scale(forZoom: 1, pixelsPerPoint: model.scale))
    }

    /// Clamped on every read, so a crop or a window resize never leaves the canvas scrolled away.
    private var viewport: Viewport {
        zoomedViewport?.clamped(to: canvasRect, in: bounds.size) ?? fitViewport
    }

    /// View points per image pixel.
    private var viewScale: CGFloat { viewport.scale }

    /// How near, in image pixels, a press must be to grab a handle.
    private var handleTolerance: CGFloat { 6 / viewScale }

    /// The canvas, in view points.
    private var imageRect: CGRect { viewport.viewRect(canvasRect) }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        viewport.imagePoint(convert(event.locationInWindow, from: nil))
    }

    private func viewRect(_ imageRect: CGRect) -> CGRect {
        viewport.viewRect(imageRect)
    }

    private func clampedToCanvas(_ point: CGPoint) -> CGPoint {
        let canvas = canvasRect
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
        var doc = model.previewDocument
        doc.canvasRect = canvasRect
        // The text being edited is drawn by its text field instead, a note's over blank paper.
        if let editingText {
            doc.annotations.removeAll { $0.id == editingText.id }
        }
        // A spotlight's dim is drawn with the document's, so its draft joins the document.
        if let draft, case .spotlight = draft.kind {
            doc.annotations.append(draft)
        }
        let rect = imageRect
        let ink = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1)
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
            AnnotationRenderer.draw(unclipped, base: doc.base, over: doc.annotations[...], in: ctx)
            ctx.restoreGState()
        }
        ink.setStroke()
        let frame = NSBezierPath(rect: rect.insetBy(dx: -0.75, dy: -0.75))
        frame.lineWidth = 1.5
        frame.stroke()

        for other in model.document.annotations where model.selectedIDs.count > 1 && model.selectedIDs.contains(other.id) {
            let outline = NSBezierPath(rect: viewRect(other.bounds.insetBy(dx: -other.lineWidth, dy: -other.lineWidth).union(other.paintedBounds)))
            outline.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
        }
        if let selected = model.selection, selected.id != editingText?.id {
            let outline = NSBezierPath(rect: viewRect(selected.bounds.insetBy(dx: -selected.lineWidth, dy: -selected.lineWidth).union(selected.paintedBounds)))
            outline.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
            if editingText == nil, !selected.isLocked {
                for handle in selected.handles {
                    let center = viewRect(CGRect(origin: handle.point, size: .zero)).origin
                    let square = NSBezierPath(rect: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                    NSColor.white.setFill()
                    square.fill()
                    square.stroke()
                }
                let radiusHandles = selected.radiusHandles(tolerance: handleTolerance)
                for handle in radiusHandles {
                    let center = viewRect(CGRect(origin: handle.point, size: .zero)).origin
                    let dot = NSBezierPath(ovalIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                    NSColor.white.setFill()
                    dot.fill()
                    dot.stroke()
                }
                if movedSinceMouseDown, let dragged = radiusHandles.first(where: { $0.handle == resizeHandle }), let radius = selected.roundedBox?.radius {
                    drawRadiusLabel(radius / model.scale, near: viewRect(CGRect(origin: dragged.point, size: .zero)).origin)
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

    /// The hand while a drag would scroll.
    private var restingCursor: NSCursor { spaceHeld || model.tool == .hand ? .openHand : .arrow }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: restingCursor)
    }

    private func beginPan(_ event: NSEvent) {
        panPoint = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.set()
    }

    private func continuePan(_ event: NSEvent) {
        guard let panPoint else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        pan(by: CGVector(dx: point.x - panPoint.x, dy: point.y - panPoint.y))
        self.panPoint = point
    }

    private func endPan() {
        panPoint = nil
        restingCursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard panPoint == nil else {
            return
        }
        if textField != nil {
            commitText()
            return
        }
        window?.makeFirstResponder(self)
        if spaceHeld || model.tool == .hand {
            beginPan(event)
            return
        }
        let point = imagePoint(event)
        dragStart = point
        lastPoint = point
        movedSinceMouseDown = false
        // The annotation just drawn stays selected, with handles that still resize it, until the next press elsewhere.
        if model.tool != .select, let selected = model.selection {
            if let handle = selected.handle(at: point, tolerance: handleTolerance) {
                resizeHandle = handle
                resizeStart = selected
                return
            }
            model.selectedID = nil
        }
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
            } else if let selected = model.selection, !selected.isLocked, let handle = selected.handle(at: point, tolerance: handleTolerance) {
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
            }
        case .counter:
            model.add(Annotation(kind: .counter(model.document.annotations.nextCounterNumber, center: point), color: model.color, lineWidth: model.lineWidth))
        case .text:
            beginText(at: point)
        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard panPoint == nil else {
            continuePan(event)
            return
        }
        guard let start = dragStart, let last = lastPoint else {
            return
        }
        let point = imagePoint(event)
        defer { lastPoint = point }
        if resizeHandle != nil {
            dragSelection(to: point, from: last)
            return
        }
        switch model.tool {
        case .select:
            dragSelection(to: point, from: last)
        case .crop:
            cropDraft = Geometry.normalized(from: clampedToCanvas(start), to: clampedToCanvas(point))
            needsDisplay = true
        case .arrow, .line, .shape, .pen, .text, .note, .highlight, .spotlight, .redact, .counter, .hand:
            // Shift keeps shapes square and lines and highlights at 45° steps; Option draws a shape out from where it started.
            // Points closer than a view point apart add nothing a stroke's curve can show.
            guard let drawn = AnnotationDraft.annotation(
                tool: model.tool, from: start, to: point, previous: draft,
                constrain: event.modifierFlags.contains(.shift), fromCenter: event.modifierFlags.contains(.option),
                minDistance: 1 / viewScale, style: model.draftStyle
            ) else {
                return
            }
            draft = drawn
            viewportDidChange()
        }
    }

    /// Resizes the selection from the handle pressed, else moves it with the pointer.
    private func dragSelection(to point: CGPoint, from last: CGPoint) {
        guard let id = model.selectedID, let index = model.document.annotations.firstIndex(where: { $0.id == id }), !model.document.annotations[index].isLocked else {
            return
        }
        if !movedSinceMouseDown {
            model.beginGesture()
            movedSinceMouseDown = true
        }
        let margin = model.canvasMargin
        if let resizeHandle, var resized = resizeStart {
            resized.resize(resizeHandle, to: point, tolerance: handleTolerance)
            model.apply { doc in
                doc.annotations[index] = resized
                doc.grow(toFit: resized, margin: margin)
                doc.shrinkPadding(margin: margin)
            }
        } else {
            model.apply { $0.move(id, by: CGVector(dx: point.x - last.x, dy: point.y - last.y), margin: margin) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if panPoint != nil {
            endPan()
            return
        }
        defer {
            draft = nil
            cropDraft = nil
            dragStart = nil
            resizeHandle = nil
            resizeStart = nil
            viewportDidChange()
        }
        if model.tool == .note, resizeHandle == nil, let start = dragStart {
            beginNote(newNote(id: draft?.id ?? UUID(), from: start, to: imagePoint(event)))
            return
        }
        if let cropDraft, cropDraft.width >= 4, cropDraft.height >= 4 {
            model.crop(to: cropDraft)
        }
        // A spotlight with no area would light nothing, so it isn't added.
        if let draft, case .spotlight = draft.kind, draft.bounds.isEmpty {
            return
        }
        if let draft, draft.bounds.width + draft.bounds.height >= 4 {
            model.add(draft)
        }
        // Each step of the move or resize already grew the canvas to fit, so ending it only records it.
        if movedSinceMouseDown {
            model.endGesture()
        }
    }

    /// The middle button scrolls with any tool, as in Figma and browsers.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, dragStart == nil, panPoint == nil else {
            super.otherMouseDown(with: event)
            return
        }
        beginPan(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard event.buttonNumber == 2, panPoint != nil else {
            super.otherMouseDragged(with: event)
            return
        }
        continuePan(event)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, panPoint != nil else {
            super.otherMouseUp(with: event)
            return
        }
        endPan()
    }

    // MARK: Dropping images

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Clipboard.hasImages(on: sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let images = Clipboard.images(on: sender.draggingPasteboard)
        guard !images.isEmpty else {
            return false
        }
        if textField != nil {
            commitText()
        }
        model.addImages(images, at: viewport.imagePoint(convert(sender.draggingLocation, from: nil)))
        window?.makeFirstResponder(self)
        return true
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
            // Escape abandons a drag under way before it deselects.
            if dragStart != nil, resizeHandle == nil, !movedSinceMouseDown {
                draft = nil
                cropDraft = nil
                dragStart = nil
                viewportDidChange()
                return
            }
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
            restingCursor.set()
        }
    }

    // Once a text field takes the keyboard, Space's release never reaches this view.
    override func resignFirstResponder() -> Bool {
        releaseSpace()
        return super.resignFirstResponder()
    }

    /// Forgets a held Space whose release this view won't see, such as when the window stops being key.
    func releaseSpace() {
        if spaceHeld {
            spaceHeld = false
            restingCursor.set()
        }
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

    /// Does nothing when the zoom wouldn't change, so a fitted canvas keeps following the window.
    private func zoom(to zoom: CGFloat, about point: CGPoint) {
        guard zoom != currentZoom else {
            return
        }
        zoomedViewport = viewport.zoomed(to: Viewport.scale(forZoom: zoom, pixelsPerPoint: model.scale), about: point).clamped(to: canvasRect, in: bounds.size)
        viewportDidChange()
    }

    /// A fitted canvas is all on screen, so it has nowhere to scroll.
    private func pan(by offset: CGVector) {
        guard zoomedViewport != nil else {
            return
        }
        zoomedViewport = viewport.panned(by: offset).clamped(to: canvasRect, in: bounds.size)
        viewportDidChange()
    }

    override func magnify(with event: NSEvent) {
        let fit = fitViewport.zoom(pixelsPerPoint: model.scale)
        zoom(to: Viewport.clampedZoom(currentZoom * (1 + event.magnification), fit: fit), about: convert(event.locationInWindow, from: nil))
    }

    /// A two-finger double-tap on a trackpad toggles between fit and actual size about the pointer.
    override func smartMagnify(with event: NSEvent) {
        if currentZoom == 1 {
            zoomToFit()
        } else {
            zoom(to: 1, about: convert(event.locationInWindow, from: nil))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // ⌘ or ⌃ with the wheel or two-finger scroll zooms about the pointer, as in Figma and Sketch.
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            let fit = fitViewport.zoom(pixelsPerPoint: model.scale)
            let perUnit: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
            let target = currentZoom * exp(event.scrollingDeltaY * perUnit)
            zoom(to: Viewport.clampedZoom(target, fit: fit), about: convert(event.locationInWindow, from: nil))
            return
        }
        guard zoomedViewport != nil else {
            super.scrollWheel(with: event)
            return
        }
        // A mouse wheel counts lines rather than points. The deltas already follow the natural scrolling setting.
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        // Shift turns a mouse wheel's vertical scroll into horizontal.
        if event.modifierFlags.contains(.shift), event.scrollingDeltaX == 0 {
            pan(by: CGVector(dx: event.scrollingDeltaY * step, dy: 0))
            return
        }
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
        if let existing {
            editingText = existing
        } else {
            var text = Annotation(kind: .text("", origin: point, fontSize: model.fontSize), color: model.color, lineWidth: model.lineWidth)
            text.alignment = model.alignment
            editingText = text
        }
        // A double-click that wobbles mustn't drag the text being edited.
        dragStart = nil
        let field = NSTextField(string: existing?.text ?? "")
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.6)
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldAction)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        layoutTextField()
    }

    /// Keeps the open text field over its text, at its size and colour, as the zoom, scroll, window or toolbar changes.
    private func layoutTextField() {
        if case .note = editingText?.kind {
            layoutNoteField()
            return
        }
        guard let field = textField, let text = editingText, case let .text(_, textOrigin, fontSize) = text.kind else {
            return
        }
        let size = fontSize * viewScale
        if field.font?.pointSize != size {
            field.font = .boldSystemFont(ofSize: size)
        }
        field.textColor = NSColor(srgbRed: text.color.r, green: text.color.g, blue: text.color.b, alpha: 1)
        field.alignment = text.alignment.textAlignment
        let origin = viewRect(CGRect(origin: textOrigin, size: .zero)).origin
        let fitted: CGFloat
        if field.stringValue.isEmpty {
            field.frame = CGRect(x: origin.x, y: origin.y, width: 240, height: size * 1.4)
            fitted = 0
        } else {
            field.sizeToFit()
            fitted = field.frame.width
            field.frame = CGRect(x: origin.x, y: origin.y, width: max(240, fitted + 20), height: field.frame.height)
        }
        // The field is wider than its text, so it reaches back past the anchor by the spare width the alignment puts before the text.
        field.frame.origin.x -= (field.frame.width - fitted) * text.alignment.fraction
    }

    @objc private func textFieldAction() {
        commitText()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            commitText()
            return true
        }
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        layoutTextField()
    }

    var isEditingText: Bool { textField != nil }

    private func commitText() {
        guard let edited = editedText else {
            return
        }
        removeTextField()
        model.commitText(edited)
    }

    /// The text or note being edited, with the text typed so far.
    private var editedText: Annotation? {
        guard var text = editingText, let field = textField else {
            return nil
        }
        text.setText(field.stringValue)
        return text
    }

    // MARK: Notes

    private func newNote(id: UUID, from start: CGPoint, to end: CGPoint) -> Annotation {
        AnnotationDraft.note(id: id, from: start, to: end, style: model.draftStyle)
    }

    /// Blank paper the size the note will be, under its text field.
    private var editingPaper: Annotation? {
        guard let note = editedText, let frame = note.noteLayout?.frame else {
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
        editingText = note
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
        guard let field = textField, let layout = editedText?.noteLayout else {
            return
        }
        // The zoom changes with the window size and the zoom commands, so the font follows it here.
        let size = layout.fontSize * viewScale
        if field.font?.pointSize != size {
            field.font = .systemFont(ofSize: size)
        }
        let ink = layout.ink
        field.textColor = NSColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: 1)
        field.alignment = (editedText?.alignment ?? .left).textAlignment
        // A borderless field insets its text 2 pt on each side.
        field.frame = viewRect(layout.textRect).insetBy(dx: -2, dy: 0)
        needsDisplay = true
    }

    private func removeTextField() {
        let field = textField
        let editedID = editingText?.id
        textField = nil
        editingText = nil
        needsDisplay = true
        field?.delegate = nil
        field?.removeFromSuperview()
        window?.makeFirstResponder(self)
        if model.tool == .select, let editedID, model.document.annotations.contains(where: { $0.id == editedID }) {
            model.selectedID = editedID
        }
    }
}

extension NSView {
    /// A chip beside `point` showing the corner radius being dragged, in points.
    func drawRadiusLabel(_ radius: CGFloat, near point: CGPoint) {
        let text = NSAttributedString(string: "Radius \(Int(radius.rounded()))", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        var chip = CGRect(x: point.x + 12, y: point.y + 12, width: (size.width + 12).rounded(), height: (size.height + 6).rounded())
        if chip.maxX > bounds.maxX {
            chip.origin.x = point.x - 12 - chip.width
        }
        if chip.maxY > bounds.maxY {
            chip.origin.y = point.y - 12 - chip.height
        }
        NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: chip.minX + 6, y: chip.minY + 3))
    }
}
