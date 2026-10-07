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
        _ = (model.selectedClipID, model.playhead, model.annotationTool, model.project, model.zoom)
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
    private var field: NSTextField?
    private var fieldIsNew = false
    /// The text or note the field is editing. The model holds it so the palette can recolour and resize it.
    private var fieldAnnotation: Annotation? {
        get { model.editingText }
        set { model.editingText = newValue }
    }

    init(model: VideoEditorModel) {
        self.model = model
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
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

    private var fit: CGFloat {
        let canvas = model.project.canvasSize
        guard canvas.width > 0, canvas.height > 0 else {
            return 1
        }
        return min(bounds.width / canvas.width, bounds.height / canvas.height)
    }

    private var origin: CGPoint {
        let canvas = model.project.canvasSize
        return CGPoint(x: (bounds.width - canvas.width * fit) / 2, y: (bounds.height - canvas.height * fit) / 2)
    }

    private func canvasPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        let canvas = model.project.canvasSize
        return CGPoint(x: min(max((point.x - origin.x) / fit, 0), canvas.width), y: min(max((point.y - origin.y) / fit, 0), canvas.height))
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        CGRect(x: origin.x + rect.minX * fit, y: origin.y + rect.minY * fit, width: rect.width * fit, height: rect.height * fit)
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
        let outline = NSBezierPath(rect: viewRect(annotation.paintedBounds))
        outline.lineWidth = 1.5
        outline.setLineDash([5, 3], count: 2, phase: 0)
        NSColor(srgbRed: 1, green: 0.83, blue: 0.23, alpha: 1).setStroke()
        outline.stroke()
        for (_, point) in annotation.handles {
            let center = CGPoint(x: origin.x + point.x * fit, y: origin.y + point.y * fit)
            let square = NSBezierPath(rect: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            NSColor.white.setFill()
            square.fill()
            NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1).setStroke()
            square.lineWidth = 1.5
            square.stroke()
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
        let tolerance = 6 / fit
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
            model.addAnnotation(Annotation(kind: .counter(model.project.nextCounterNumber, center: point), color: model.annotationStyle.color, lineWidth: model.lineWidth))
            dragStart = nil
        case .text:
            beginField(for: Annotation(kind: .text("", origin: point, fontSize: model.fontSize), color: model.annotationStyle.color, lineWidth: model.lineWidth), isNew: true)
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
        var point = canvasPoint(event)
        defer { lastPoint = point }
        // Shift keeps shapes square and lines and highlights at 45° steps; Option draws a shape out from where it started.
        let constrain = event.modifierFlags.contains(.shift)
        let fromCenter = event.modifierFlags.contains(.option)
        var rect = Geometry.normalized(from: start, to: point)
        switch tool {
        case .shape, .redact, .spotlight:
            if constrain {
                rect = Geometry.square(from: start, to: point)
            }
            if fromCenter {
                let corner = constrain ? CGPoint(x: rect.minX == start.x ? rect.maxX : rect.minX, y: rect.minY == start.y ? rect.maxY : rect.minY) : point
                rect = Geometry.normalized(from: CGPoint(x: 2 * start.x - corner.x, y: 2 * start.y - corner.y), to: corner)
            }
        case .arrow, .line:
            if constrain {
                point = Geometry.snapped(from: start, to: point)
            }
        default:
            break
        }
        let style = model.annotationStyle
        let kind: Annotation.Kind
        switch tool {
        case .select:
            guard let clip = selected else {
                return
            }
            var changed = editing ?? clip.annotation
            if let resizeHandle, let resizeStart {
                changed = resizeStart
                changed.resize(resizeHandle, to: point)
            } else {
                changed.offset(by: CGVector(dx: point.x - last.x, dy: point.y - last.y))
            }
            editing = changed
            model.previewAnnotation(changed, replacing: clip.id)
            needsDisplay = true
            return
        case .crop, .counter, .text:
            return
        case .arrow: kind = .arrow(from: start, to: point)
        case .line: kind = .line(from: start, to: point)
        case .shape: kind = .shape(style.shape, rect: rect)
        case .highlight:
            if constrain {
                kind = .marker([start, Geometry.snapped(from: start, to: point)])
            } else if let draft, case let .marker(drawn) = draft.kind {
                kind = .marker(Freehand.adding(point, to: drawn, minDistance: 1 / fit))
            } else {
                kind = .marker([start, point])
            }
        case .redact: kind = style.redaction == .blur ? .blur(rect) : .pixelate(rect)
        case .spotlight: kind = .spotlight(rect, style: model.nextSpotlightStyle)
        case .pen:
            let points: [CGPoint]
            if let draft, case let .freehand(drawn) = draft.kind {
                points = drawn
            } else {
                points = [start]
            }
            kind = .freehand(Freehand.adding(point, to: points, minDistance: 1 / fit))
        case .note:
            var note = Annotation(id: draft?.id ?? UUID(), kind: .note("", rect: .zero), color: style.noteColor, lineWidth: model.lineWidth)
            note.kind = .note("", rect: NoteLayout.placementRect(from: start, to: point, fontSize: note.noteFontSize))
            draft = note
            model.previewAnnotation(note)
            return
        }
        var shape = Annotation(id: draft?.id ?? UUID(), kind: kind, color: model.nextColor, lineWidth: model.lineWidth)
        if shape.supportsFill {
            shape.fill = style.fill
        }
        draft = shape
        model.previewAnnotation(shape)
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
        let field = NSTextField(string: annotation.text ?? "")
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(fieldAction)
        if case .note = annotation.kind {
            field.drawsBackground = false
            field.usesSingleLineMode = false
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.maximumNumberOfLines = 0
            field.lineBreakMode = .byWordWrapping
            field.placeholderString = "Note"
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
        // The preview hides the annotation being edited, since its field is drawn over where it was.
        if !isNew {
            model.previewAnnotation(nil)
            model.hideAnnotation(annotation.id)
        }
    }

    func layoutField() {
        guard let field, let annotation = fieldAnnotation else {
            return
        }
        var edited = annotation
        edited.setText(field.stringValue)
        switch annotation.kind {
        case .note:
            guard let layout = edited.noteLayout else {
                return
            }
            let size = layout.fontSize * fit
            if field.font?.pointSize != size {
                field.font = .systemFont(ofSize: size)
            }
            let ink = layout.ink
            field.textColor = NSColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: 1)
            // A borderless field insets its text 2 pt on each side.
            field.frame = viewRect(layout.textRect).insetBy(dx: -2, dy: 0)
        case let .text(_, origin, fontSize):
            let size = fontSize * fit
            if field.font?.pointSize != size {
                field.font = .boldSystemFont(ofSize: size)
            }
            field.textColor = NSColor(srgbRed: annotation.color.r, green: annotation.color.g, blue: annotation.color.b, alpha: 1)
            field.sizeToFit()
            let topLeft = viewRect(CGRect(origin: origin, size: .zero)).origin
            field.frame = CGRect(x: topLeft.x, y: topLeft.y, width: max(200, field.frame.width + 20), height: size * 1.4)
        default:
            break
        }
    }

    @objc private func fieldAction() {
        commitField()
    }

    func controlTextDidChange(_ notification: Notification) {
        layoutField()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            closeField()
            model.previewAnnotation(nil)
            return true
        }
        return false
    }

    private func commitField() {
        guard let field, var annotation = fieldAnnotation else {
            return
        }
        let string = field.stringValue
        let isNew = fieldIsNew
        closeField()
        annotation.setText(string)
        if isNew {
            if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.previewAnnotation(nil)
            } else {
                model.addAnnotation(annotation)
            }
        } else {
            model.commitAnnotation(annotation, id: annotation.id)
        }
    }

    private func closeField() {
        let old = field
        field = nil
        fieldAnnotation = nil
        old?.delegate = nil
        old?.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}

private extension Annotation {
    var isEditableText: Bool { text != nil }
}
