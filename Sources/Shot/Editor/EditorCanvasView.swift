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
    private var resizeHandle: NoteHandle?

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
                self?.needsDisplay = true
                self?.observe()
            }
        }
    }

    override func layout() {
        super.layout()
        layoutNoteField()
        needsDisplay = true
    }

    // MARK: Geometry

    /// View points per image pixel.
    private var viewScale: CGFloat {
        let canvas = model.document.canvasRect
        let fit = min((bounds.width - 40) / canvas.width, (bounds.height - 40) / canvas.height)
        return max(0.01, min(fit, 1 / model.scale))
    }

    private var imageRect: CGRect {
        let canvas = model.document.canvasRect
        let s = viewScale
        let size = CGSize(width: canvas.width * s, height: canvas.height * s)
        return CGRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let rect = imageRect
        let canvas = model.document.canvasRect
        return CGPoint(x: canvas.minX + (p.x - rect.minX) / viewScale, y: canvas.minY + (p.y - rect.minY) / viewScale)
    }

    private func viewRect(_ imageRect: CGRect) -> CGRect {
        let rect = self.imageRect
        let canvas = model.document.canvasRect
        let s = viewScale
        return CGRect(x: rect.minX + (imageRect.minX - canvas.minX) * s, y: rect.minY + (imageRect.minY - canvas.minY) * s, width: imageRect.width * s, height: imageRect.height * s)
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
        ctx.interpolationQuality = .high
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

        if let id = model.selectedID, let selected = model.document.annotations.first(where: { $0.id == id }) {
            let outline = NSBezierPath(rect: viewRect(selected.bounds.insetBy(dx: -selected.lineWidth, dy: -selected.lineWidth)))
            outline.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
            if case .note = selected.kind, editingNote == nil {
                for handle in NoteHandle.allCases {
                    let center = viewRect(CGRect(origin: handle.point(in: selected.bounds), size: .zero)).origin
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
        let point = imagePoint(event)
        dragStart = point
        lastPoint = point
        movedSinceMouseDown = false
        switch model.tool {
        case .select:
            let tolerance = 6 / viewScale
            let hit = model.document.annotations.topmostIndex(at: point, tolerance: tolerance).map { model.document.annotations[$0] }
            if event.clickCount == 2, let hit, case .note = hit.kind {
                model.selectedID = hit.id
                beginNote(hit)
            } else if let id = model.selectedID, let selected = model.document.annotations.first(where: { $0.id == id }), let handle = selected.noteHandle(at: point, tolerance: tolerance) {
                resizeHandle = handle
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
            if let resizeHandle {
                model.document.annotations[index].resizeNote(resizeHandle, to: point)
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
        case .note:
            draft = newNote(id: draft?.id ?? UUID(), from: start, to: point)
            needsDisplay = true
            return
        }
        draft = Annotation(id: draft?.id ?? UUID(), kind: kind, color: model.color, lineWidth: model.lineWidth)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            draft = nil
            cropDraft = nil
            dragStart = nil
            resizeHandle = nil
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
        if let draft, draft.bounds.width + draft.bounds.height >= 4 {
            model.add(draft)
        }
        // The move or resize recorded its undo step when it began, so growing joins that step.
        if model.tool == .select, movedSinceMouseDown, let id = model.selectedID, let moved = model.document.annotations.first(where: { $0.id == id }) {
            model.document.grow(toFit: moved, margin: model.canvasMargin)
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            model.deleteSelection()
            return
        }
        if event.keyCode == 53 {
            model.selectedID = nil
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if modifiers.isEmpty, let character = event.charactersIgnoringModifiers?.lowercased().first, let tool = EditorTool.allCases.first(where: { $0.key == character }) {
            model.tool = tool
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Text

    private func beginText(at point: CGPoint) {
        textOrigin = point
        let field = NSTextField(string: "")
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.6)
        field.focusRingType = .none
        let rgba = model.color
        field.textColor = NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: 1)
        field.font = .boldSystemFont(ofSize: model.fontSize * viewScale)
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldAction)
        let origin = viewRect(CGRect(origin: point, size: .zero)).origin
        field.frame = CGRect(x: origin.x, y: origin.y, width: 240, height: model.fontSize * viewScale * 1.4)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
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
        field.sizeToFit()
        field.frame.size.width = max(240, field.frame.width + 20)
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
        removeTextField()
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
        note.setNoteText(field.stringValue)
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
        // The zoom changes when the window resizes, so the font follows it here.
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
            model.setNoteText(note.id, to: string)
        } else if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var placed = note
            placed.setNoteText(string)
            model.add(placed)
        }
    }

    private func removeTextField() {
        let field = textField
        textField = nil
        textOrigin = nil
        editingNote = nil
        needsDisplay = true
        field?.delegate = nil
        field?.removeFromSuperview()
        window?.makeFirstResponder(self)
    }
}
