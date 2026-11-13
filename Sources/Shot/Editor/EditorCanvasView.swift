import AppKit
import QuartzCore
import ShotCore

final class EditorCanvasView: NSView, NSTextFieldDelegate {
    private let model: EditorModel
    private var draft: Annotation?
    /// A counter popping in as it lands, and when it was placed. Only drawing changes: the document already holds it whole.
    private var landing: (id: UUID, start: CFTimeInterval)?
    private var landingLink: CADisplayLink?
    /// What dragging in crop mode does, decided where the press landed, with the crop as it was then.
    private enum CropDrag {
        case handle(CropHandle, start: CGRect)
        case move(start: CGRect, from: CGPoint)
        case draw(start: CGRect)
    }
    private var cropDrag: CropDrag?
    private var dragStart: CGPoint?
    private var lastPoint: CGPoint?
    private var movedSinceMouseDown = false
    /// Text or a note pressed with the text or note tool. A drag moves it, and a click edits it only if it was already
    /// selected, so which one is only known when the button comes up.
    private var pressedText: Annotation?
    private var pressedTextWasSelected = false
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
    /// While Space is held during a resize, the pointer moves the whole shape: where it was pressed, and the shape then.
    private var spaceMove: (origin: CGPoint, shape: Annotation)?
    /// The zoom and scroll position, or nil to fit the canvas to the view as it resizes.
    /// They're view state, not part of the document, so they aren't undoable.
    private var zoomedViewport: Viewport?
    /// True while Space is held, when a drag scrolls instead of using the tool.
    private var spaceHeld = false
    /// The last view point of a scroll by dragging: with Space held, the hand tool or the middle button.
    private var panPoint: CGPoint?
    /// Told where the canvas is, in view points, so the backdrop behind it draws its shadow there.
    var onImageRectChange: ((CGRect) -> Void)?
    /// The placed image the pointer is over, which shows its crop badge when it has a crop of its own.
    private var hoveredImageID: UUID? {
        didSet {
            if hoveredImageID != oldValue {
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
            }
        }
    }
    private var hoverArea: NSTrackingArea?

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
            _ = model.cropDraft
            _ = model.cropBarClearance
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
    /// and as a style previewed in the Style panel would make it.
    private var canvasRect: CGRect { displayDocument.canvasRect }

    /// What the canvas draws: the previewed document grown for the pending draft. In crop mode it's uncropped, so
    /// everything shows, and the crop is drawn over it; cropping a placed image shows all of that image.
    private var displayDocument: EditorDocument {
        var doc = model.previewDocument
        for pending in [draft, editingPaper].compactMap({ $0 }) {
            doc.grow(toFit: pending, margin: model.canvasMargin)
        }
        if model.tool == .crop {
            doc.isFrameCropHidden = true
            if let id = model.cropImageID, let index = doc.annotations.firstIndex(where: { $0.id == id }),
               case let .image(image, _) = doc.annotations[index].kind, let full = doc.annotations[index].imageFullRect {
                doc.annotations[index].kind = .image(image, rect: full)
                doc.annotations[index].imageCrop = nil
                doc.grow(toFit: doc.annotations[index], margin: model.canvasMargin)
            }
        }
        return doc
    }

    /// The whole canvas, no larger than actual size.
    private var fitViewport: Viewport {
        .fit(canvasRect, in: viewportSize, maxScale: Viewport.scale(forZoom: 1, pixelsPerPoint: model.scale))
    }

    /// Clamped on every read, so a crop or a window resize never leaves the canvas scrolled away.
    private var viewport: Viewport {
        zoomedViewport?.clamped(to: canvasRect, in: viewportSize) ?? fitViewport
    }

    /// The room the image fits and scrolls in: the view above the crop bar in crop mode, so the crop's bottom handles
    /// never sit under it, and all of it otherwise.
    private var viewportSize: CGSize {
        CGSize(width: bounds.width, height: max(1, bounds.height - (model.tool == .crop ? model.cropBarClearance : 0)))
    }

    /// View points per image pixel.
    private var viewScale: CGFloat { viewport.scale }

    /// How near, in image pixels, a press must be to grab a handle.
    private var handleTolerance: CGFloat { 6 / viewScale }
    /// How far, in view points, a press on text or a note has to move before it counts as a drag.
    private static let dragThreshold: CGFloat = 4

    /// The topmost text or note under `point`.
    private func textOrNote(at point: CGPoint) -> Annotation? {
        guard let index = model.document.annotations.topmostIndex(at: point, tolerance: handleTolerance) else {
            return nil
        }
        let hit = model.document.annotations[index]
        switch hit.kind {
        case .text, .note: return hit
        default: return nil
        }
    }

    /// The canvas, in view points.
    private var imageRect: CGRect { viewport.viewRect(canvasRect) }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        viewport.imagePoint(convert(event.locationInWindow, from: nil))
    }

    private func viewRect(_ imageRect: CGRect) -> CGRect {
        viewport.viewRect(imageRect)
    }

    // MARK: Drawing

    /// Pops the counter `id` in over 200 ms with a small overshoot. Reduce Motion shows it at once.
    private func land(_ id: UUID) {
        guard !Motion.reduced else {
            return
        }
        landing = (id, CACurrentMediaTime())
        if landingLink == nil {
            let link = displayLink(target: self, selector: #selector(landingFrame))
            link.add(to: .main, forMode: .common)
            landingLink = link
        }
    }

    @objc private func landingFrame(_ link: CADisplayLink) {
        needsDisplay = true
        guard let landing, CACurrentMediaTime() - landing.start < Moment.markLand.duration else {
            landing = nil
            landingLink?.invalidate()
            landingLink = nil
            return
        }
    }

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
        var doc = displayDocument
        if let landing, let index = doc.annotations.firstIndex(where: { $0.id == landing.id }) {
            let progress = (CACurrentMediaTime() - landing.start) / Moment.markLand.duration
            doc.annotations[index] = doc.annotations[index].scaled(by: Moment.popScale(progress))
        }
        // The text being edited is drawn by its text field instead, a note's over blank paper.
        if let editingText {
            doc.annotations.removeAll { $0.id == editingText.id }
        }
        // A spotlight's dim is drawn with the document's, so its draft joins the document.
        if let draft, case .spotlight = draft.kind {
            doc.annotations.append(draft)
        }
        let rect = imageRect
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
        drawImageEdge(around: rect)

        for other in model.document.annotations where model.selectedIDs.count > 1 && model.selectedIDs.contains(other.id) {
            SelectionStyle.outline(viewRect(other.bounds.insetBy(dx: -other.lineWidth, dy: -other.lineWidth).union(other.paintedBounds)))
        }
        if let selected = model.selection, selected.id != editingText?.id {
            SelectionStyle.outline(viewRect(selected.bounds.insetBy(dx: -selected.lineWidth, dy: -selected.lineWidth).union(selected.paintedBounds)))
            if editingText == nil, !selected.isLocked {
                for handle in selected.handles {
                    SelectionStyle.handle(at: viewRect(CGRect(origin: handle.point, size: .zero)).origin)
                }
                let radiusHandles = selected.radiusHandles(tolerance: handleTolerance)
                for handle in radiusHandles {
                    SelectionStyle.handle(at: viewRect(CGRect(origin: handle.point, size: .zero)).origin, round: true)
                }
                if movedSinceMouseDown, let dragged = radiusHandles.first(where: { $0.handle == resizeHandle }), let radius = selected.cornerBox?.radius {
                    drawRadiusLabel(radius / model.scale, near: viewRect(CGRect(origin: dragged.point, size: .zero)).origin)
                }
            }
        }
        for badge in cropBadges {
            drawCropBadge(at: badge.center)
        }
        if model.tool == .crop, let cropDraft = model.cropDraft {
            drawCrop(viewRect(cropDraft), over: viewRect(cropBounds), in: ctx)
        }
    }

    // MARK: Crop badges

    /// The crop badges showing, with their centres in view points: one on each placed image with its own crop that the
    /// pointer is over or that's selected. There are none in crop mode, while text is typed, or while a drag moves or
    /// resizes something.
    private var cropBadges: [(id: UUID, center: CGPoint)] {
        guard model.tool != .crop, editingText == nil, !(dragStart != nil && movedSinceMouseDown) else {
            return []
        }
        // The single selection shows its resize handles, so its badge steps out past the corner one.
        let withHandles = model.selection.flatMap { $0.isLocked ? nil : $0.id }
        return model.document.annotations.compactMap { annotation in
            let selected = model.selectedIDs.contains(annotation.id)
            guard CanvasCropBadge.shows(on: annotation, selected: selected, hovered: annotation.id == hoveredImageID) else {
                return nil
            }
            // An image scrolled wholly out of view has no badge; one partly in view keeps its badge inside the edge.
            let rect = viewRect(annotation.bounds)
            guard rect.intersects(bounds) else {
                return nil
            }
            return (annotation.id, CanvasCropBadge.center(of: rect, clearOfHandle: annotation.id == withHandles, in: bounds))
        }
    }

    /// The image whose crop badge is under `viewPoint`, if any.
    private func cropBadge(at viewPoint: CGPoint) -> UUID? {
        cropBadges.last { CanvasCropBadge.contains(viewPoint, center: $0.center) }?.id
    }

    /// The board's badge: an 18 pt white circle with a 1 pt edge of ink at 20% and a small drop, holding the crop symbol
    /// in 85% ink. Dark mode uses the floating pills' `#2C2C30` and the light ink, and Increase Contrast a 60% edge.
    private func drawCropBadge(at center: CGPoint) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let size = CanvasCropBadge.diameter
        let box = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        let circle = NSBezierPath(ovalIn: box)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.4 : 0.2)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        (dark ? Self.badgeDarkFill : NSColor.white).setFill()
        circle.fill()
        NSGraphicsContext.restoreGraphicsState()
        let ink = dark ? Self.lightInk : Theme.inkNS
        let edge = increased ? ink.withAlphaComponent(0.6) : (dark ? NSColor.white.withAlphaComponent(0.18) : ink.withAlphaComponent(0.2))
        edge.setStroke()
        let rim = NSBezierPath(ovalIn: box.insetBy(dx: 0.5, dy: 0.5))
        rim.lineWidth = 1
        rim.stroke()
        let symbolColor = increased || dark ? ink : NSColor(srgbRed: 0x3A / 255, green: 0x39 / 255, blue: 0x3F / 255, alpha: 1)
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold).applying(.init(paletteColors: [symbolColor]))
        guard let symbol = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
            return
        }
        let symbolSize = symbol.size
        symbol.draw(
            in: CGRect(x: center.x - symbolSize.width / 2, y: center.y - symbolSize.height / 2, width: symbolSize.width, height: symbolSize.height),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
        )
    }

    private static let badgeDarkFill = NSColor(srgbRed: 0x2C / 255, green: 0x2C / 255, blue: 0x30 / 255, alpha: 1)
    private static let lightInk = NSColor(srgbRed: 0xED / 255, green: 0xEB / 255, blue: 0xE6 / 255, alpha: 1)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if hoverArea == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area)
            hoverArea = area
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let viewPoint = convert(event.locationInWindow, from: nil)
        // A badge already showing keeps its image hovered, since it reaches past the image's corner.
        if let badge = cropBadge(at: viewPoint) {
            hoveredImageID = badge
            setToolTip(String(localized: "Crop Image"))
            return
        }
        setToolTip(nil)
        let point = viewport.imagePoint(viewPoint)
        let hit = model.document.annotations.topmostIndex(at: point, tolerance: handleTolerance).map { model.document.annotations[$0] }
        hoveredImageID = hit?.imageFullRect != nil ? hit?.id : nil
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoveredImageID = nil
        setToolTip(nil)
    }

    private func setToolTip(_ tip: String?) {
        if toolTip != tip {
            toolTip = tip
        }
    }

    /// The board's hairline just outside the image: ink at 8% (dark white at 10%, half as thick), and 50% ink under
    /// Increase Contrast. The backdrop draws the soft shadow under it.
    private func drawImageEdge(around rect: CGRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let width: CGFloat = dark ? 0.5 : 1
        let color: NSColor = if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            (dark ? NSColor.white : Theme.inkNS).withAlphaComponent(0.5)
        } else {
            dark ? NSColor.white.withAlphaComponent(0.1) : Theme.inkNS.withAlphaComponent(0.08)
        }
        color.setStroke()
        let edge = NSBezierPath(rect: rect.insetBy(dx: -width / 2, dy: -width / 2))
        edge.lineWidth = width
        edge.stroke()
    }

    /// Washes what `crop` leaves out of `canvas`, the canvas or the image being cropped, in the backdrop's colour, and
    /// draws the crop as on Edit › Image editor · crop and combine: a 1.5 pt ink outline with a 1 pt edge outside it in
    /// the opposite colour, a thirds grid, ink L-shaped corners and a short bar in the middle of each side.
    private func drawCrop(_ crop: CGRect, over canvas: CGRect, in ctx: CGContext) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let outside = NSBezierPath(rect: canvas)
        outside.append(NSBezierPath(rect: crop))
        outside.windingRule = .evenOdd
        ctx.saveGState()
        outside.addClip()
        let wash = dark ? NSColor(srgbRed: 0x15 / 255, green: 0x15 / 255, blue: 0x17 / 255, alpha: 1) : NSColor(srgbRed: 0xEC / 255, green: 0xEA / 255, blue: 0xE5 / 255, alpha: 1)
        wash.withAlphaComponent(increased ? 0.85 : 0.72).setFill()
        canvas.fill()
        ctx.restoreGState()

        // The thirds grid, white at 80% (all white under Increase Contrast), inside the crop.
        NSColor.white.withAlphaComponent(increased ? 1 : 0.8).setFill()
        for third in [1.0 / 3, 2.0 / 3] {
            NSRect(x: (crop.minX + crop.width * third).rounded() - 0.5, y: crop.minY, width: 1, height: crop.height).fill()
            NSRect(x: crop.minX, y: (crop.minY + crop.height * third).rounded() - 0.5, width: crop.width, height: 1).fill()
        }

        // The ink, light in dark mode, with an edge of the opposite colour outside it, so the outline and marks show on
        // any screenshot.
        let ink = dark ? NSColor(srgbRed: 0xED / 255, green: 0xEB / 255, blue: 0xE6 / 255, alpha: 1) : Theme.inkNS
        let edge: NSColor = dark ? .black : .white
        edge.setStroke()
        let halo = NSBezierPath(rect: crop.insetBy(dx: -0.5, dy: -0.5))
        halo.lineWidth = 1
        halo.stroke()
        ink.setStroke()
        let outline = NSBezierPath(rect: crop.insetBy(dx: 0.75, dy: 0.75))
        outline.lineWidth = 1.5
        outline.stroke()

        ink.setFill()
        for path in Self.cropMarks(crop) {
            edge.setStroke()
            path.lineWidth = 2
            path.stroke()
            path.fill()
        }
    }

    /// The crop's corners and side bars, in view points, from ShotCore's `CropMarks`, which the video editor shares.
    /// Their hit areas are the handles'.
    private static func cropMarks(_ crop: CGRect) -> [NSBezierPath] {
        let corners = CropMarks.corners(of: crop).map { points in
            let path = NSBezierPath()
            path.move(to: points[0])
            points.dropFirst().forEach { path.line(to: $0) }
            path.close()
            return path
        }
        let bars = CropMarks.bars(of: crop).map { NSBezierPath(roundedRect: $0, xRadius: CropMarks.barRadius, yRadius: CropMarks.barRadius) }
        return corners + bars
    }

    /// Where a press in crop mode lands decides whether dragging resizes, moves or redraws the crop.
    private func beginCropDrag(at point: CGPoint) {
        guard let crop = model.cropDraft else {
            return
        }
        if let handle = CropGeometry.handle(at: point, in: crop, tolerance: handleTolerance) {
            cropDrag = .handle(handle, start: crop)
        } else if crop.contains(point), crop != cropBounds {
            // A crop holding all the content has nowhere to move, so a drag inside it draws a new one.
            cropDrag = .move(start: crop, from: point)
        } else {
            cropDrag = .draw(start: crop)
        }
    }

    /// How far the crop can reach: the canvas, or all of the placed image being cropped.
    private var cropBounds: CGRect { model.cropImageFullRect ?? canvasRect }

    /// Edges stick to the image's edges.
    private var cropSnap: CropSnap {
        let image = model.cropImageFullRect ?? model.document.fullRect
        return CropSnap(xs: [image.minX, image.maxX], ys: [image.minY, image.maxY], tolerance: 6 / viewScale)
    }

    private func dragCrop(to point: CGPoint, from start: CGPoint, shift: Bool) {
        guard let cropDrag else {
            return
        }
        let bounds = cropBounds
        // A picked shape holds the crop to it; Shift keeps the shape the crop had, or draws a square.
        func ratio(_ size: CGSize) -> CGFloat? {
            model.cropAspect.ratio(for: size) ?? (shift ? size.width / max(size.height, 1) : nil)
        }
        switch cropDrag {
        case let .handle(handle, startCrop):
            model.cropDraft = CropGeometry.resize(startCrop, handle: handle, to: point, within: bounds, ratio: ratio(startCrop.size), snap: cropSnap)
        case let .move(startCrop, from):
            model.cropDraft = CropGeometry.move(startCrop, dx: point.x - from.x, dy: point.y - from.y, within: bounds, snap: cropSnap)
        case .draw:
            let dragged = CGSize(width: abs(point.x - start.x), height: abs(point.y - start.y))
            let shape: CGFloat? = model.cropAspect.ratio(for: dragged) ?? (shift ? 1 : nil)
            if let drawn = CropGeometry.draw(from: start, to: point, within: bounds, ratio: shape, snap: cropSnap),
               drawn.width >= CropGeometry.minimumSize, drawn.height >= CropGeometry.minimumSize {
                model.cropDraft = drawn
            }
        }
    }

    // MARK: Mouse

    /// The hand while a drag would scroll.
    private var restingCursor: NSCursor { spaceHeld || model.tool == .hand ? .openHand : .arrow }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: restingCursor)
        guard !spaceHeld, model.tool != .hand else {
            return
        }
        let size = CanvasCropBadge.diameter
        for badge in cropBadges {
            addCursorRect(CGRect(x: badge.center.x - size / 2, y: badge.center.y - size / 2, width: size, height: size), cursor: .pointingHand)
        }
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
        // The crop badge adjusts its image's crop, whichever tool is picked, as the Layers panel's badge does.
        if let badge = cropBadge(at: convert(event.locationInWindow, from: nil)) {
            movedSinceMouseDown = false
            model.cropImage(badge)
            return
        }
        let point = imagePoint(event)
        dragStart = point
        lastPoint = point
        movedSinceMouseDown = false
        let selectedBeforePress = model.selectedID
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
            } else if event.clickCount == 2, let hit, case .image = hit.kind, !hit.isLocked {
                dragStart = nil
                model.cropImage(hit.id)
            } else if let selected = model.selection, !selected.isLocked, let handle = selected.handle(at: point, tolerance: handleTolerance) {
                resizeHandle = handle
                resizeStart = selected
            } else if let hit {
                model.selectedID = hit.id
            } else {
                model.selectedID = nil
            }
        case .crop:
            // A press outside the canvas puts the crop down.
            guard imageRect.contains(convert(event.locationInWindow, from: nil)) else {
                dragStart = nil
                model.applyCrop()
                return
            }
            beginCropDrag(at: point)
        case .note:
            // Clicking a note with the note tool edits it rather than stacking a new one on top.
            pressedText = textOrNote(at: point)
            pressedTextWasSelected = pressedText?.id == selectedBeforePress
            if let pressedText {
                model.selectedID = pressedText.id
            }
        case .counter:
            let counter = Annotation(kind: .counter(model.document.annotations.nextCounterNumber, center: point), color: model.color, lineWidth: model.lineWidth)
            model.add(counter)
            land(counter.id)
        case .text:
            // Pressing existing text selects it to move or edit instead of starting more text on top of it.
            pressedText = textOrNote(at: point)
            pressedTextWasSelected = pressedText?.id == selectedBeforePress
            if let pressedText {
                model.selectedID = pressedText.id
            } else {
                beginText(at: point)
            }
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
        if pressedText != nil {
            // A press that barely moves is still a click.
            guard movedSinceMouseDown || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold / viewScale else {
                return
            }
            dragSelection(to: point, from: last, modifiers: event.modifierFlags)
            lastPoint = point
            return
        }
        defer { lastPoint = point }
        if resizeHandle != nil {
            dragSelection(to: point, from: last, modifiers: event.modifierFlags)
            return
        }
        switch model.tool {
        case .select:
            dragSelection(to: point, from: last, modifiers: event.modifierFlags)
        case .crop:
            dragCrop(to: point, from: start, shift: event.modifierFlags.contains(.shift))
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

    /// Resizes the selection from the handle pressed, else moves it with the pointer. Shift keeps proportions or snaps
    /// to 45°, and Option resizes from the centre; see `Annotation.resize`. Space moves the shape instead of resizing it.
    private func dragSelection(to point: CGPoint, from last: CGPoint, modifiers: NSEvent.ModifierFlags) {
        guard let id = model.selectedID, let index = model.document.annotations.firstIndex(where: { $0.id == id }), !model.document.annotations[index].isLocked else {
            return
        }
        if !movedSinceMouseDown {
            model.beginGesture()
            movedSinceMouseDown = true
        }
        let margin = model.canvasMargin
        if let resizeHandle, var resized = resizeStart {
            if let spaceMove {
                resized = spaceMove.shape
                resized.offset(by: CGVector(dx: point.x - spaceMove.origin.x, dy: point.y - spaceMove.origin.y))
            } else {
                resized.resize(resizeHandle, to: point, tolerance: handleTolerance, constrain: modifiers.contains(.shift), fromCenter: modifiers.contains(.option))
            }
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
            cropDrag = nil
            dragStart = nil
            resizeHandle = nil
            resizeStart = nil
            spaceMove = nil
            pressedText = nil
            viewportDidChange()
        }
        if let pressedText, resizeHandle == nil {
            if movedSinceMouseDown {
                model.endGesture()
            } else if pressedTextWasSelected {
                // A second click on a selected note, which a double-click also is, edits it and deselects it.
                model.selectedID = nil
                if case .note = pressedText.kind {
                    beginNote(pressedText)
                } else if case let .text(_, origin, _) = pressedText.kind {
                    beginText(at: origin, editing: pressedText)
                }
            }
            return
        }
        if model.tool == .note, resizeHandle == nil, let start = dragStart {
            beginNote(newNote(id: draft?.id ?? UUID(), from: start, to: imagePoint(event)))
            return
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

    // MARK: Context menu

    /// Right-clicking a placed image offers to crop it, or to show all of it again.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard model.tool != .crop, textField == nil else {
            return nil
        }
        let point = imagePoint(event)
        guard let index = model.document.annotations.topmostIndex(at: point, tolerance: 6 / viewScale) else {
            return nil
        }
        let hit = model.document.annotations[index]
        guard hit.imageFullRect != nil, !hit.isLocked else {
            return nil
        }
        model.selectedIDs = [hit.id]
        let menu = NSMenu()
        let crop = NSMenuItem(title: String(localized: "Crop Image"), action: #selector(cropImageFromMenu(_:)), keyEquivalent: "")
        crop.target = self
        crop.representedObject = hit.id
        menu.addItem(crop)
        if hit.imageCrop != nil {
            let reset = NSMenuItem(title: String(localized: "Reset Crop"), action: #selector(resetImageCropFromMenu(_:)), keyEquivalent: "")
            reset.target = self
            reset.representedObject = hit.id
            menu.addItem(reset)
        }
        return menu
    }

    @objc private func cropImageFromMenu(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else {
            return
        }
        model.cropImage(id)
        window?.makeFirstResponder(self)
    }

    @objc private func resetImageCropFromMenu(_ item: NSMenuItem) {
        if let id = item.representedObject as? UUID {
            model.resetImageCrop(id)
        }
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
            } else if resizeHandle != nil, spaceMove == nil, !event.isARepeat, let last = lastPoint,
                      let id = model.selectedID, let shape = model.document.annotations.first(where: { $0.id == id }) {
                spaceMove = (last, shape)
            }
            return
        }
        if model.tool == .crop {
            // Return keeps the crop, Escape drops what was changed, and Delete takes the crop off.
            switch event.keyCode {
            case 36, 76:
                model.applyCrop()
                return
            case 53:
                cropDrag = nil
                dragStart = nil
                model.cancelCrop()
                return
            case 51, 117:
                model.resetCrop()
                return
            default:
                break
            }
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            model.deleteSelection()
            return
        }
        if event.keyCode == 53 {
            // Escape abandons a drag under way before it deselects.
            if dragStart != nil, resizeHandle == nil, !movedSinceMouseDown {
                draft = nil
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
        if modifiers.isEmpty, let tool = event.charactersIgnoringModifiers.flatMap(EditorTool.init(key:)) {
            model.tool = tool
            return
        }
        super.keyDown(with: event)
    }

    /// Pressing or releasing Shift or Option mid-resize updates the shape at once, without waiting for the pointer to move.
    override func flagsChanged(with event: NSEvent) {
        if resizeHandle != nil, movedSinceMouseDown, panPoint == nil, let last = lastPoint {
            dragSelection(to: last, from: last, modifiers: event.modifierFlags)
        }
        super.flagsChanged(with: event)
    }

    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49 else {
            super.keyUp(with: event)
            return
        }
        // Letting go of Space puts the shape where it was moved to, and resizing carries on from the pointer.
        if let spaceMove, let last = lastPoint {
            resizeStart?.offset(by: CGVector(dx: last.x - spaceMove.origin.x, dy: last.y - spaceMove.origin.y))
            self.spaceMove = nil
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

    // MARK: Accessibility

    /// One element per visible annotation, kept by id so VoiceOver's cursor stays on it as the document changes.
    private var annotationElements: [UUID: AnnotationAccessibilityElement] = [:]

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { String(localized: "Canvas") }

    /// Top layer first, as the layers panel lists them.
    override func accessibilityChildren() -> [Any]? {
        let visible = model.layers.filter { !$0.isHidden }
        annotationElements = visible.reduce(into: [:]) { elements, annotation in
            let element = annotationElements[annotation.id] ?? AnnotationAccessibilityElement(id: annotation.id) { [weak self] id in
                self?.model.selectLayers([id])
            }
            element.setAccessibilityParent(self)
            element.setAccessibilityLabel(annotation.layerName)
            element.setAccessibilityRoleDescription(annotation.accessibilityKind)
            element.setAccessibilityValue(Self.accessibilityText(of: annotation))
            element.setAccessibilitySelected(model.selectedIDs.contains(annotation.id))
            element.setAccessibilityFrame(NSAccessibility.screenRect(fromView: self, rect: viewRect(annotation.bounds)))
            elements[annotation.id] = element
        }
        return visible.compactMap { annotationElements[$0.id] }
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        _ = accessibilityChildren()
        return model.selectedIDs.compactMap { annotationElements[$0] }
    }

    /// All of a text's or note's words, which its name cuts short.
    private static func accessibilityText(of annotation: Annotation) -> String? {
        switch annotation.kind {
        case let .text(string, _, _), let .note(string, _): string
        case .arrow, .line, .shape, .highlight, .pixelate, .blur, .spotlight, .counter, .freehand, .marker, .image: nil
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
        zoomedViewport = viewport.zoomed(to: Viewport.scale(forZoom: zoom, pixelsPerPoint: model.scale), about: point).clamped(to: canvasRect, in: viewportSize)
        viewportDidChange()
    }

    /// A fitted canvas is all on screen, so it has nowhere to scroll.
    private func pan(by offset: CGVector) {
        guard zoomedViewport != nil else {
            return
        }
        zoomedViewport = viewport.panned(by: offset).clamped(to: canvasRect, in: viewportSize)
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

    /// Shows the new zoom in the zoom control, moves the image's shadow, and keeps an open text field over its text.
    private func viewportDidChange() {
        let zoom = currentZoom
        if model.zoom != zoom {
            model.zoom = zoom
        }
        layoutTextField()
        updateStyleBar()
        onImageRectChange?(imageRect)
        needsDisplay = true
    }

    /// Tells the style bar where the mark it styles is, and to step aside while a drag draws, moves, resizes or crops.
    private func updateStyleBar() {
        let dragging = dragStart != nil && (draft != nil || movedSinceMouseDown || cropDrag != nil)
        if model.isCanvasDragging != dragging {
            model.isCanvasDragging = dragging
        }
        let mark = (editingPaper ?? editedText ?? model.selection).flatMap { annotation -> CGRect? in
            let bounds = annotation.bounds
            guard !bounds.isNull else {
                return nil
            }
            let outline = viewRect(bounds.insetBy(dx: -annotation.lineWidth / 2, dy: -annotation.lineWidth / 2))
            return outline.insetBy(dx: -StyleBarPlacement.markPadding, dy: -StyleBarPlacement.markPadding)
        }
        if model.styleBarMark != mark {
            model.styleBarMark = mark
        }
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
        if commandSelector == #selector(NSResponder.insertNewline(_:)), case .note = editingText?.kind, NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        }
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        layoutTextField()
        updateStyleBar()
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
        guard case let .note(string, _) = note.kind, note.noteLayout != nil else {
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
        field.placeholderString = String(localized: "Note")
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
        field.frame = viewRect(layout.alignedTextRect).insetBy(dx: -2, dy: 0)
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
        let text = NSAttributedString(string: String(localized: "Radius \(Int(radius.rounded()))"), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: Preferences().textSize.points(11), weight: .semibold),
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
        Theme.inkNS.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: chip.minX + 6, y: chip.minY + 3))
    }
}

/// An annotation as VoiceOver sees it on the canvas. Pressing it selects it, as clicking it with the select tool does.
private final class AnnotationAccessibilityElement: NSAccessibilityElement {
    let id: UUID
    private let select: (UUID) -> Void

    init(id: UUID, select: @escaping (UUID) -> Void) {
        self.id = id
        self.select = select
        super.init()
        setAccessibilityRole(.image)
        setAccessibilityEnabled(true)
    }

    override func accessibilityPerformPress() -> Bool {
        select(id)
        return true
    }
}
