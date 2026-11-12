import AppKit
import ShotCore

/// Pick Colour's loupe over a still of every display (Capture › Permission card, colour loupe…): the pixels round the
/// pointer in a round grid centred on it, the middle pixel's colour and hex in a label below, and a hint. A click, Return or
/// Space picks the middle pixel, the arrow keys move the pointer a pixel at a time, and Esc cancels.
@MainActor
final class ColorPickerOverlay {
    /// What the pick is for, which the hint names: copying its hex, or setting a colour in the editor.
    enum Purpose {
        case copy
        case pick
    }

    let purpose: Purpose
    private var panels: [OverlayPanel] = []
    private var views: [ColorPickerView] = []
    private var continuation: CheckedContinuation<RGBA?, Never>?

    private init(purpose: Purpose) {
        self.purpose = purpose
    }

    /// The colour of the pixel picked on one of `displays`, in sRGB, or nil when the person cancels. Each display needs its
    /// frozen image.
    static func pick(displays: [OverlayDisplay], purpose: Purpose) async -> RGBA? {
        let overlay = ColorPickerOverlay(purpose: purpose)
        // The views hold the overlay unowned; keep it alive until the person picks or cancels.
        let color = await withCheckedContinuation { continuation in
            overlay.continuation = continuation
            overlay.show(displays)
        }
        withExtendedLifetime(overlay) {}
        return color
    }

    private func show(_ displays: [OverlayDisplay]) {
        for display in displays {
            guard let image = display.image else {
                continue
            }
            let panel = OverlayPanel(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            let bounds = NSRect(origin: .zero, size: display.frame.size)
            let content = NSView(frame: bounds)
            content.wantsLayer = true
            // The still sits in its own view, so moving the loupe doesn't redraw it.
            let frozen = NSImageView(frame: bounds)
            frozen.image = NSImage(cgImage: image, size: bounds.size)
            frozen.imageScaling = .scaleAxesIndependently
            frozen.autoresizingMask = [.width, .height]
            content.addSubview(frozen)
            let view = ColorPickerView(frame: bounds, image: image, scale: display.scale, overlay: self)
            view.autoresizingMask = [.width, .height]
            content.addSubview(view)
            panel.contentView = content
            panel.setFrame(display.frame, display: false)
            panels.append(panel)
            views.append(view)
        }
        guard !panels.isEmpty else {
            finish(nil)
            return
        }
        for panel in panels {
            panel.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        let index = panels.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
        let panel = panels[index], view = views[index]
        panel.makeKey()
        panel.makeFirstResponder(view)
        view.pointer = panel.convertPoint(fromScreen: mouse)
        view.needsDisplay = true
        ColorPickerView.cursor.set()
    }

    func finish(_ color: RGBA?) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
        continuation.resume(returning: color)
    }
}

/// One display's loupe. The pointer is hidden while it's on the overlay, since the loupe's middle cell marks the pixel.
final class ColorPickerView: NSView {
    private let image: CGImage
    private let scale: CGFloat
    private unowned let overlay: ColorPickerOverlay
    /// Where the pointer is in this view, or nil while it's on another display.
    var pointer: CGPoint? {
        didSet {
            let hex = color?.hex
            if accessibilityValue() as? String != hex {
                setAccessibilityValue(hex)
            }
        }
    }

    init(frame: NSRect, image: CGImage, scale: CGFloat, overlay: ColorPickerOverlay) {
        self.image = image
        self.scale = scale
        self.overlay = overlay
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Pick Colour"))
        setAccessibilityHelp(String(localized: "Move the pointer or press the arrow keys to choose a pixel. Click or press Return to pick its colour. Esc cancels."))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        Self.cursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        pointer = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        // A tracking area added under the pointer can report an exit straight away; only a real one clears the loupe.
        if let window, NSMouseInRect(NSEvent.mouseLocation, window.frame, false) {
            return
        }
        pointer = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        overlay.finish(color)
    }

    override func rightMouseDown(with event: NSEvent) {
        overlay.finish(nil)
    }

    /// Esc can arrive as this rather than as a key press, as in the pin and recording panels.
    override func cancelOperation(_ sender: Any?) {
        overlay.finish(nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            overlay.finish(nil)
        case 36, 76, 49:
            overlay.finish(color)
        case 123, 124, 125, 126:
            // One device pixel a press, or ten with Shift, so a pixel can be reached exactly without the mouse.
            let step = (event.modifierFlags.contains(.shift) ? 10 : 1) / scale
            let dx: CGFloat = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
            let dy: CGFloat = event.keyCode == 125 ? -step : event.keyCode == 126 ? step : 0
            nudge(dx: dx, dy: dy)
        default:
            super.keyDown(with: event)
        }
    }

    /// Moves the pointer itself, so the next mouse move carries on from there, and says the new colour to VoiceOver.
    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard let window else {
            return
        }
        let start = pointer ?? convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let inset = 0.5 / scale
        let moved = CGPoint(x: min(max(start.x + dx, inset), bounds.width - inset), y: min(max(start.y + dy, inset), bounds.height - inset))
        let onScreen = window.convertPoint(toScreen: convert(moved, to: nil))
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: onScreen.x, y: primaryHeight - onScreen.y))
        // A warp holds back mouse events for a moment; let them through at once.
        CGAssociateMouseAndMouseCursorPosition(1)
        pointer = moved
        needsDisplay = true
        if let hex = color?.hex {
            NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
                .announcement: hex,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
    }

    private var imageSize: CGSize { CGSize(width: image.width, height: image.height) }

    /// The colour of the device pixel under the pointer.
    private var color: RGBA? {
        guard let pointer else {
            return nil
        }
        let pixel = Loupe.pixel(at: pointer, viewHeight: bounds.height, scale: scale, imageSize: imageSize)
        return PixelColor.sRGB(of: image, x: pixel.x, y: pixel.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let pointer, let color, let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }
        let textSize = Preferences().textSize
        let backing = window?.backingScaleFactor ?? 2
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let cell = ColorLoupe.cell(side: textSize.points(ColorLoupe.side))
        let side = cell * CGFloat(Loupe.cells)
        let inkRing = Brutal.inkWidth(1.5, scale: backing)
        let outset = 3 + inkRing

        let hex = NSAttributedString(string: color.hex, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: textSize.points(12.5), weight: .bold), .foregroundColor: NSColor.white,
        ])
        let hexSize = hex.size()
        let swatch = textSize.points(16)
        let labelSize = CGSize(width: (5 + swatch + 8 + hexSize.width + 10).rounded(.up), height: (max(swatch, hexSize.height) + 8).rounded(.up))
        let hint = NSAttributedString(string: hintText, attributes: [
            .font: NSFont.systemFont(ofSize: textSize.points(11.5)), .foregroundColor: Self.hintText,
        ])
        let hintTextSize = hint.size()
        let hintSize = CGSize(width: (hintTextSize.width + 16).rounded(.up), height: (hintTextSize.height + 4).rounded(.up))
        let layout = ColorLoupe.layout(pointer: pointer, side: side, outset: outset, label: labelSize, hint: hintSize, in: bounds)
        let loupe = layout.loupe

        // The rings, with the board's `0 12px 28px rgba(0,0,0,0.3)` under the outer one.
        ctx.saveGState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.shadowBlurRadius = 14
        shadow.set()
        ctx.setFillColor(Brutal.inkNS.cgColor)
        ctx.fillEllipse(in: loupe.insetBy(dx: -outset, dy: -outset))
        ctx.restoreGState()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: loupe.insetBy(dx: -3, dy: -3))

        // The pixels, one a cell. A pixel near the screen's edge stays in the middle, with black beyond the edge.
        ctx.saveGState()
        ctx.addEllipse(in: loupe)
        ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(loupe)
        let pixel = Loupe.pixel(at: pointer, viewHeight: bounds.height, scale: scale, imageSize: imageSize)
        if let placed = Loupe.destination(of: Loupe.source(around: pixel), imageSize: imageSize, in: loupe), let crop = image.cropping(to: placed.crop) {
            ctx.interpolationQuality = .none
            ctx.draw(crop, in: placed.rect)
        }
        // The board's grid is ink at 6%, which vanishes over dark pixels, so it's mid-grey to show over both, as in the
        // area overlay's loupe.
        ctx.setFillColor(NSColor(white: 0.5, alpha: 0.3).cgColor)
        let hairline = 1 / backing
        for step in 1..<Loupe.cells {
            let offset = CGFloat(step) * cell
            ctx.fill(CGRect(x: loupe.minX + offset - hairline / 2, y: loupe.minY, width: hairline, height: side))
            ctx.fill(CGRect(x: loupe.minX, y: loupe.minY + offset - hairline / 2, width: side, height: hairline))
        }
        // The middle pixel: 1.5 pt of ink round it, then 1.5 pt of white, both outside it so its colour shows whole.
        let middle = CGFloat(Loupe.cells / 2)
        let centre = CGRect(x: loupe.minX + middle * cell, y: loupe.minY + middle * cell, width: cell, height: cell)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(inkRing)
        ctx.stroke(centre.insetBy(dx: -inkRing * 1.5, dy: -inkRing * 1.5))
        ctx.setStrokeColor(Brutal.inkNS.cgColor)
        ctx.stroke(centre.insetBy(dx: -inkRing / 2, dy: -inkRing / 2))
        ctx.restoreGState()

        // The label: a floating-panel pill with a swatch of the colour and its hex.
        let label = layout.label
        let pill = NSBezierPath(roundedRect: label, xRadius: 9, yRadius: 9)
        FloatingPanel.fillNS(0.92, solid: FloatingPanel.solidNS).setFill()
        pill.fill()
        FloatingPanel.edgeNS(increased: increased).setStroke()
        let edge = NSBezierPath(roundedRect: label.insetBy(dx: 0.25, dy: 0.25), xRadius: 9, yRadius: 9)
        edge.lineWidth = 0.5
        edge.stroke()
        let swatchRect = CGRect(x: label.minX + 5, y: (label.midY - swatch / 2).rounded(), width: swatch, height: swatch)
        NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1).setFill()
        NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4).fill()
        NSColor.white.withAlphaComponent(increased ? 0.8 : 0.4).setStroke()
        let swatchEdge = NSBezierPath(roundedRect: swatchRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5)
        swatchEdge.lineWidth = 1
        swatchEdge.stroke()
        hex.draw(at: CGPoint(x: swatchRect.maxX + 8, y: (label.midY - hexSize.height / 2).rounded()))

        // The hint, on a light pill so it reads over the dark label and any content; solid with Increase Contrast or
        // Reduce Transparency.
        let hintRect = layout.hint
        let hintPill = NSBezierPath(roundedRect: hintRect, xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(FloatingPanel.solidNS ? 1 : 0.85).setFill()
        hintPill.fill()
        if increased {
            Brutal.inkNS.withAlphaComponent(0.4).setStroke()
            hintPill.lineWidth = 1
            hintPill.stroke()
        }
        hint.draw(at: CGPoint(x: hintRect.minX + 8, y: (hintRect.midY - hintTextSize.height / 2).rounded()))
    }

    private var hintText: String {
        switch overlay.purpose {
        case .copy: String(localized: "Click to copy · Esc to cancel")
        case .pick: String(localized: "Click to pick · Esc to cancel")
        }
    }

    /// The board's hint text, `#3A393F`.
    private static let hintText = NSColor(srgbRed: 0x3A / 255, green: 0x39 / 255, blue: 0x3F / 255, alpha: 1)

    /// An empty cursor: the loupe's middle cell shows where the pointer is.
    static let cursor = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)
}
