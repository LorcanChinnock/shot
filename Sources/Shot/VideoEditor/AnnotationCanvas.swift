import AppKit
import ShotCore
import SwiftUI

/// Sits over the player while a tool is picked: draws new annotations at the playhead, and selects, moves and resizes
/// the ones showing there. The compositor draws them live through `VideoEditorModel.previewAnnotation`.
struct AnnotationCanvas: NSViewRepresentable {
    let model: VideoEditorModel

    func makeNSView(context: Context) -> AnnotationCanvasView {
        AnnotationCanvasView(model: model)
    }

    func updateNSView(_ view: AnnotationCanvasView, context: Context) {
        // Reading these makes SwiftUI call this again when they change, so the handles follow the selection and playhead.
        // Only while annotating: otherwise there are no handles, and playback would redraw the canvas every tick.
        if model.isAnnotating {
            _ = (model.selectedClipID, model.playhead, model.project, model.zoom)
        }
        // The palette recolours and resizes the text being typed.
        _ = model.editingText
        view.layoutField()
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    private let model: VideoEditorModel
    private var dragStart: CGPoint?
    private var lastPoint: CGPoint?
    private var draft: Annotation?
    /// The selected annotation as it's being moved or resized, before it's committed.
    private var editing: Annotation?
    private var resizeHandle: AnnotationHandle?
    private var resizeStart: Annotation?
    private var field: RunsTextField?
    private var fieldIsNew = false
    /// The text or note the field is editing. The model holds it so the palette can recolour and resize it.
    private var fieldAnnotation: Annotation? {
        get { model.editingText }
        set { model.editingText = newValue }
    }

    init(model: VideoEditorModel) {
        self.model = model
        super.init(frame: .zero)
        model.commitPendingText = { [weak self] in self?.commitField() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Clicks pass through to what's under the canvas unless a tool is picked.
    override func hitTest(_ point: NSPoint) -> NSView? {
        model.isAnnotating ? super.hitTest(point) : nil
    }

    override func resetCursorRects() {
        guard let tool = model.annotationTool else {
            return
        }
        addCursorRect(bounds, cursor: tool == .select ? .arrow : .crosshair)
    }

    // MARK: Canvas and view

    /// The part of the canvas the player shows, aspect-fitted and centred in the view, matching the player under it, so
    /// no inset.
    private var viewport: Viewport {
        let frame = model.shownFrame
        guard frame.width > 0, frame.height > 0 else {
            return Viewport(scale: 1, origin: .zero)
        }
        let fit = min(bounds.width / frame.width, bounds.height / frame.height)
        return Viewport(scale: fit, origin: CGPoint(x: (bounds.width - frame.width * fit) / 2 - frame.minX * fit, y: (bounds.height - frame.height * fit) / 2 - frame.minY * fit))
    }

    private var fit: CGFloat { viewport.scale }

    private func canvasPoint(_ event: NSEvent) -> CGPoint {
        let point = viewport.imagePoint(convert(event.locationInWindow, from: nil))
        let canvas = model.project.canvasSize
        return CGPoint(x: min(max(point.x, 0), canvas.width), y: min(max(point.y, 0), canvas.height))
    }

    /// How near, in canvas pixels, a press must be to grab a handle.
    private var handleTolerance: CGFloat { 6 / fit }

    private func viewRect(_ rect: CGRect) -> CGRect {
        viewport.viewRect(rect)
    }

    /// The annotation clip showing at the playhead that the selection is, if it is one.
    private var selected: AnnotationClip? {
        guard let clip = model.selectedAnnotation, clip.start <= model.playhead, model.playhead < clip.end else {
            return nil
        }
        return clip
    }

    // MARK: Drawing the handles

    override func draw(_ dirtyRect: NSRect) {
        guard model.isAnnotating, let clip = selected, field == nil else {
            return
        }
        let annotation = editing ?? clip.annotation
        SelectionStyle.outline(viewRect(annotation.paintedBounds))
        for (_, point) in annotation.handles {
            SelectionStyle.handle(at: viewport.viewPoint(point))
        }
        let radiusHandles = annotation.radiusHandles(tolerance: handleTolerance)
        for (_, point) in radiusHandles {
            SelectionStyle.handle(at: viewport.viewPoint(point), round: true)
        }
        if editing != nil, let dragged = radiusHandles.first(where: { $0.handle == resizeHandle }), let radius = annotation.cornerBox?.radius {
            drawRadiusLabel(radius / model.styleScale, near: viewport.viewPoint(dragged.point))
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if field != nil {
            commitField()
            return
        }
        guard let tool = model.annotationTool else {
            return
        }
        model.pauseForEditing()
        let point = canvasPoint(event)
        dragStart = point
        lastPoint = point
        let tolerance = handleTolerance
        switch tool {
        case .select:
            let visible = model.project.annotationClips(at: model.playhead)
            let hit = visible.last { $0.annotation.hitTest(point, tolerance: tolerance) }
            if event.clickCount == 2, let hit, hit.annotation.isEditableText {
                model.selectClip(hit.id)
                beginField(for: hit.annotation, isNew: false)
                dragStart = nil
            } else if let clip = selected, let handle = clip.annotation.handle(at: point, tolerance: tolerance) {
                resizeHandle = handle
                resizeStart = clip.annotation
            } else if let hit {
                model.selectClip(hit.id)
            } else {
                model.selectClip(nil as UUID?)
            }
        case .counter:
            model.addAnnotation(Annotation(kind: .counter(model.project.nextCounterNumber, center: point), color: model.nextColor, lineWidth: model.lineWidth))
            dragStart = nil
        case .text:
            var text = Annotation(kind: .text("", origin: point, fontSize: model.fontSize), color: model.nextColor, lineWidth: model.lineWidth)
            text.alignment = model.annotationStyle.alignment
            beginField(for: text, isNew: true)
            dragStart = nil
        case .note:
            // Clicking a note with the note tool edits it rather than stacking another on top.
            if let hit = model.project.annotationClips(at: model.playhead).last(where: { clip in
                if case .note = clip.annotation.kind { clip.annotation.hitTest(point, tolerance: tolerance) } else { false }
            }) {
                model.selectClip(hit.id)
                beginField(for: hit.annotation, isNew: false)
                dragStart = nil
            } else {
                model.selectClip(nil as UUID?)
            }
        default:
            model.selectClip(nil as UUID?)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let last = lastPoint, let tool = model.annotationTool else {
            return
        }
        let point = canvasPoint(event)
        defer { lastPoint = point }
        switch tool {
        case .select:
            guard let clip = selected else {
                return
            }
            var changed = editing ?? clip.annotation
            if let resizeHandle, let resizeStart {
                changed = resizeStart
                changed.resize(resizeHandle, to: point, tolerance: handleTolerance)
            } else {
                changed.offset(by: CGVector(dx: point.x - last.x, dy: point.y - last.y))
            }
            editing = changed
            model.previewAnnotation(changed, replacing: clip.id)
            needsDisplay = true
        case .crop, .hand, .counter, .text:
            return
        case .arrow, .line, .shape, .highlight, .redact, .spotlight, .pen, .note:
            // Shift keeps shapes square and lines and highlights at 45° steps; Option draws a shape out from where it started.
            guard let drawn = AnnotationDraft.annotation(
                tool: tool, from: start, to: point, previous: draft,
                constrain: event.modifierFlags.contains(.shift), fromCenter: event.modifierFlags.contains(.option),
                minDistance: 1 / fit, style: model.draftStyle
            ) else {
                return
            }
            draft = drawn
            model.previewAnnotation(drawn)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            draft = nil
            editing = nil
            dragStart = nil
            resizeHandle = nil
            resizeStart = nil
            needsDisplay = true
        }
        if let editing, let clip = selected {
            model.commitAnnotation(editing, id: clip.id)
            return
        }
        guard let draft else {
            return
        }
        if case .note = draft.kind {
            beginField(for: draft, isNew: true)
            return
        }
        // A spotlight with no area would light nothing, so it isn't added.
        if case .spotlight = draft.kind, draft.bounds.isEmpty {
            model.previewAnnotation(nil)
            return
        }
        if draft.bounds.width + draft.bounds.height >= 4 {
            model.addAnnotation(draft)
        } else {
            model.previewAnnotation(nil)
        }
    }

    // MARK: Text and notes

    /// Opens a text field over a text or note annotation, which is either new or already on the timeline.
    private func beginField(for annotation: Annotation, isNew: Bool) {
        let field = RunsTextField(annotation: annotation)
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = self
        field.onFinish = { [weak self] in self?.commitField() }
        field.onSelectionChange = { [weak self] in self?.syncField() }
        field.onSizesChange = { [weak self] in
            self?.syncField()
            self?.layoutField()
        }
        if case .note = annotation.kind {
            field.drawsBackground = false
            field.usesSingleLineMode = false
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            field.placeholderString = String(localized: "Note")
        } else {
            field.drawsBackground = true
            field.backgroundColor = NSColor.white.withAlphaComponent(0.6)
        }
        addSubview(field)
        self.field = field
        fieldAnnotation = annotation
        fieldIsNew = isNew
        layoutField()
        window?.makeFirstResponder(field)
        syncField()
        // The preview hides the annotation being edited, since its field is drawn over where it was.
        if !isNew {
            model.previewAnnotation(nil)
            model.hideAnnotation(annotation.id)
        }
    }

    /// The text or note being edited, with what's typed so far in its sizes.
    private var editedField: Annotation? {
        guard let field, var annotation = fieldAnnotation else {
            return nil
        }
        annotation.setText(field.text, runs: field.sizes)
        return annotation
    }

    /// Tells the model the text being typed, in its sizes, and what's selected in it, for the style bar.
    private func syncField() {
        if let edited = editedField, edited != fieldAnnotation {
            fieldAnnotation = edited
        }
        if model.editingSelection != field?.selection {
            model.editingSelection = field?.selection
        }
    }

    func layoutField() {
        guard let field, let annotation = fieldAnnotation else {
            return
        }
        // The palette may have resized what's typed; the field takes its sizes first.
        if let runs = annotation.textRuns {
            field.setSizes(runs)
        }
        guard let edited = editedField else {
            return
        }
        switch annotation.kind {
        case .note:
            guard let layout = edited.noteLayout else {
                return
            }
            let ink = layout.ink
            field.restyle(
                emptySize: layout.fontSize, color: NSColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: 1),
                alignment: annotation.alignment.textAlignment, viewScale: fit
            )
            // A borderless field insets its text 2 pt on each side.
            field.frame = viewRect(layout.alignedTextRect).insetBy(dx: -2, dy: 0)
        case let .text(_, origin, fontSize):
            field.restyle(
                emptySize: fontSize, color: NSColor(srgbRed: annotation.color.r, green: annotation.color.g, blue: annotation.color.b, alpha: 1),
                alignment: annotation.alignment.textAlignment, viewScale: fit
            )
            let layout = TextLayout(string: field.text, fontSize: fontSize, color: annotation.color, runs: field.sizes)
            // A borderless field insets its text 2 pt on each side.
            let box = viewRect(CGRect(origin: origin, size: layout.size)).insetBy(dx: -2, dy: 0)
            field.frame = RunsTextField.frame(unwrapping: box, isEmpty: field.text.isEmpty, alignment: annotation.alignment, minWidth: 200)
        default:
            break
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        syncField()
        layoutField()
    }

    /// Esc and ⌘Return keep the text, as they do in the image editor; an empty new label goes away. Return starts a new line.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        (control as? RunsTextField)?.perform(commandSelector, in: textView) ?? false
    }

    private func commitField() {
        guard let field, let annotation = editedField else {
            return
        }
        let string = field.text
        let isNew = fieldIsNew
        closeField()
        if isNew {
            if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.previewAnnotation(nil)
            } else {
                model.addAnnotation(annotation)
            }
        } else {
            // An unchanged label isn't a new project, so committing leaves it hidden; show it again instead.
            let unchanged = model.project.annotationClip(annotation.id)?.annotation == annotation
            model.commitAnnotation(annotation, id: annotation.id)
            if unchanged {
                model.previewAnnotation(nil)
            }
        }
    }

    private func closeField() {
        let old = field
        field = nil
        fieldAnnotation = nil
        model.editingSelection = nil
        old?.delegate = nil
        old?.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}

private extension Annotation {
    var isEditableText: Bool { text != nil }
}
