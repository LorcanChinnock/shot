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
            _ = model.document.crop
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

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }
        var doc = model.document
        if let draft {
            doc.annotations.append(draft)
        }
        let rect = imageRect
        let ink = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1)
        ink.setFill()
        rect.offsetBy(dx: 5, dy: 5).fill()
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: viewScale, y: -viewScale)
        ctx.interpolationQuality = .high
        AnnotationRenderer.render(doc, into: ctx)
        ctx.restoreGState()
        ink.setStroke()
        let frame = NSBezierPath(rect: rect.insetBy(dx: -1.25, dy: -1.25))
        frame.lineWidth = 2.5
        frame.stroke()

        if let id = model.selectedID, let selected = model.document.annotations.first(where: { $0.id == id }) {
            let outline = NSBezierPath(rect: viewRect(selected.bounds.insetBy(dx: -selected.lineWidth, dy: -selected.lineWidth)))
            outline.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
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
            if let index = model.document.annotations.topmostIndex(at: point, tolerance: tolerance) {
                model.selectedID = model.document.annotations[index].id
            } else {
                model.selectedID = nil
            }
        case .counter:
            model.recordUndo()
            let counter = Annotation(kind: .counter(model.document.annotations.nextCounterNumber, center: point), color: model.color, lineWidth: model.lineWidth)
            model.document.annotations.append(counter)
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
            model.document.annotations[index].offset(by: CGVector(dx: point.x - last.x, dy: point.y - last.y))
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
        }
        draft = Annotation(id: draft?.id ?? UUID(), kind: kind, color: model.color, lineWidth: model.lineWidth)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            draft = nil
            cropDraft = nil
            dragStart = nil
            needsDisplay = true
        }
        if let cropDraft, cropDraft.width >= 4, cropDraft.height >= 4 {
            model.recordUndo()
            model.document.crop = cropDraft.integral.intersection(model.document.fullRect)
        }
        if let draft, draft.bounds.width + draft.bounds.height >= 4 {
            model.recordUndo()
            model.document.annotations.append(draft)
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
        field.sizeToFit()
        field.frame.size.width = max(240, field.frame.width + 20)
    }

    var isEditingText: Bool { textField != nil }

    private func commitText() {
        guard let field = textField, let origin = textOrigin else {
            return
        }
        let string = field.stringValue
        removeTextField()
        guard !string.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        model.recordUndo()
        model.document.annotations.append(Annotation(kind: .text(string, origin: origin, fontSize: model.fontSize), color: model.color, lineWidth: model.lineWidth))
    }

    private func removeTextField() {
        let field = textField
        textField = nil
        textOrigin = nil
        field?.delegate = nil
        field?.removeFromSuperview()
        window?.makeFirstResponder(self)
    }
}
