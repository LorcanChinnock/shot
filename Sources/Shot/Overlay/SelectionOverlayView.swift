import AppKit
import ShotCore

final class SelectionOverlayView: NSView {
    let display: OverlayDisplay
    private let index: Int
    private unowned let controller: SelectionOverlayController

    private let showMagnifier = Preferences().showMagnifier
    private let showCrosshair = Preferences().showCrosshair
    private var pointer: CGPoint?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var isMoving = false
    private var lastDragPoint: CGPoint?
    private var portrait: Bool?
    var magnifierImage: CGImage? {
        didSet { needsDisplay = true }
    }

    private static let minimumSize: CGFloat = 4
    private static let orientationLockDistance: CGFloat = 8
    private static let loupeSize: CGFloat = 120
    private static let loupeZoom: CGFloat = 8

    init(frame: NSRect, display: OverlayDisplay, index: Int, controller: SelectionOverlayController) {
        self.display = display
        self.index = index
        self.controller = controller
        super.init(frame: frame)
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
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        if controller.windowMode {
            controller.updateHover()
        } else {
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        pointer = point
        if controller.windowMode {
            return
        }
        dragStart = point
        lastDragPoint = point
        portrait = nil
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !controller.windowMode, let start = dragStart else {
            return
        }
        let point = clamped(convert(event.locationInWindow, from: nil))
        pointer = point
        if isMoving, let current = selection, let last = lastDragPoint {
            var moved = current.offsetBy(dx: point.x - last.x, dy: point.y - last.y)
            moved.origin.x = min(max(moved.minX, 0), bounds.width - moved.width)
            moved.origin.y = min(max(moved.minY, 0), bounds.height - moved.height)
            dragStart = CGPoint(x: start.x + moved.minX - current.minX, y: start.y + moved.minY - current.minY)
            selection = moved
        } else {
            if portrait == nil, hypot(point.x - start.x, point.y - start.y) >= Self.orientationLockDistance {
                portrait = isTall(from: start, to: point)
            }
            selection = shaped(from: start, to: point, square: event.modifierFlags.contains(.shift))
        }
        lastDragPoint = point
        needsDisplay = true
    }

    private func shaped(from start: CGPoint, to point: CGPoint, square: Bool) -> CGRect {
        if square {
            return Geometry.fitted(from: start, to: point, ratio: 1, in: bounds)
        }
        if let ratio = controller.aspectRatio.value {
            let tall = portrait ?? isTall(from: start, to: point)
            return Geometry.fitted(from: start, to: point, ratio: tall ? 1 / ratio : ratio, in: bounds)
        }
        return Geometry.normalized(from: start, to: point)
    }

    private func isTall(from start: CGPoint, to point: CGPoint) -> Bool {
        abs(point.y - start.y) > abs(point.x - start.x)
    }

    override func mouseUp(with event: NSEvent) {
        if controller.windowMode {
            if let window = controller.hoveredWindow {
                controller.finish(.window(window), modifiers: event.modifierFlags)
            }
            return
        }
        defer {
            dragStart = nil
            isMoving = false
        }
        guard let selection, selection.width >= Self.minimumSize, selection.height >= Self.minimumSize else {
            self.selection = nil
            needsDisplay = true
            return
        }
        let shape = event.modifierFlags.contains(.shift) ? AspectRatio.square : controller.aspectRatio
        let ratio = shape.value.map { selection.width >= selection.height ? $0 : 1 / $0 }
        controller.finish(.area(display: index, rect: selection, ratio: ratio), modifiers: event.modifierFlags)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            controller.finish(nil)
        case 49:
            if dragStart != nil {
                isMoving = true
            } else if !event.isARepeat {
                controller.toggleWindowMode()
            }
        case 48 where !controller.windowMode:
            controller.aspectRatio = controller.aspectRatio.next(backward: event.modifierFlags.contains(.shift))
            if let start = dragStart, let point = lastDragPoint, !isMoving {
                portrait = isTall(from: start, to: point)
                selection = shaped(from: start, to: point, square: false)
            }
            needsDisplay = true
        case 7 where controller.aspectRatio != .free:
            if let start = dragStart, let point = lastDragPoint, !isMoving {
                portrait = !(portrait ?? isTall(from: start, to: point))
                selection = shaped(from: start, to: point, square: event.modifierFlags.contains(.shift))
                needsDisplay = true
            }
        case 36, 76:
            if controller.isLive {
                controller.finish(.fullDisplay(index), modifiers: event.modifierFlags)
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isMoving = false
        }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }
        ctx.clear(dirtyRect)

        let hole = holeRect()
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole {
            dim.addRect(hole)
        }
        ctx.addPath(dim)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fillPath(using: .evenOdd)

        if let hole {
            if controller.windowMode {
                ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.25).cgColor)
                ctx.fill(hole)
            }
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(hole.insetBy(dx: 0.5, dy: 0.5))
        }

        drawHint(in: ctx)
        guard let pointer, !controller.windowMode else {
            return
        }
        if selection == nil {
            if showCrosshair {
                drawCrosshair(at: pointer, in: ctx)
            }
            if showMagnifier {
                drawLoupe(at: pointer, in: ctx)
            }
        } else if let selection {
            drawSizeLabel(for: selection, near: pointer)
        }
    }

    private func holeRect() -> CGRect? {
        if controller.windowMode {
            guard let window = controller.hoveredWindow else {
                return nil
            }
            let global = controller.appKitFrame(of: window)
            let local = global.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY).intersection(bounds)
            return local.isNull ? nil : local
        }
        return selection
    }

    private func drawCrosshair(at point: CGPoint, in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 0, y: point.y.rounded() + 0.5))
        ctx.addLine(to: CGPoint(x: bounds.width, y: point.y.rounded() + 0.5))
        ctx.move(to: CGPoint(x: point.x.rounded() + 0.5, y: 0))
        ctx.addLine(to: CGPoint(x: point.x.rounded() + 0.5, y: bounds.height))
        ctx.strokePath()
    }

    private func drawLoupe(at point: CGPoint, in ctx: CGContext) {
        guard let image = display.image ?? magnifierImage else {
            return
        }
        let size = Self.loupeSize
        var origin = CGPoint(x: point.x + 20, y: point.y - size - 20)
        if origin.x + size > bounds.width {
            origin.x = point.x - size - 20
        }
        if origin.y < 0 {
            origin.y = point.y + 20
        }
        let loupe = CGRect(origin: origin, size: CGSize(width: size, height: size))
        let sourceSide = size / Self.loupeZoom
        let source = Geometry.pixelRect(
            forViewRect: CGRect(x: point.x - sourceSide / 2, y: point.y - sourceSide / 2, width: sourceSide, height: sourceSide),
            viewHeight: bounds.height,
            scale: display.scale
        )
        ctx.saveGState()
        ctx.addEllipse(in: loupe)
        ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(loupe)
        if let crop = image.cropping(to: source) {
            ctx.interpolationQuality = .none
            ctx.draw(crop, in: loupe)
        }
        let pixel = size / (sourceSide * display.scale)
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: loupe.midX - pixel / 2, y: loupe.midY - pixel / 2, width: pixel, height: pixel))
        ctx.restoreGState()
        ctx.setStrokeColor(Self.ink.cgColor)
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: loupe.insetBy(dx: -1.5, dy: -1.5))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: loupe.insetBy(dx: 0.75, dy: 0.75))
    }

    private static let ink = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1)
    private static let yellow = NSColor(srgbRed: 1, green: 0.83, blue: 0.23, alpha: 1)

    /// Neo-brutalist chip: flat fill, ink border, hard offset shadow.
    private func drawChip(_ text: String, at origin: CGPoint, fill: NSColor, font: NSFont) -> CGRect {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: Self.ink])
        let size = string.size()
        let box = CGRect(x: origin.x, y: origin.y, width: (size.width + 20).rounded(), height: (size.height + 10).rounded())
        Self.ink.setFill()
        NSBezierPath(roundedRect: box.offsetBy(dx: 3, dy: -3), xRadius: 7, yRadius: 7).fill()
        fill.setFill()
        let shape = NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7)
        shape.fill()
        Self.ink.setStroke()
        shape.lineWidth = 2
        shape.stroke()
        string.draw(at: CGPoint(x: box.minX + 10, y: box.minY + 5))
        return box
    }

    private func drawSizeLabel(for selection: CGRect, near point: CGPoint) {
        var text = "\(Int((selection.width * display.scale).rounded())) × \(Int((selection.height * display.scale).rounded()))"
        if controller.aspectRatio != .free {
            text = "\(controller.aspectRatio.label(portrait: selection.height > selection.width)) · \(text)"
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width + 20
        var origin = CGPoint(x: point.x + 16, y: point.y - 44)
        if origin.x + width > bounds.width {
            origin.x = point.x - width - 16
        }
        if origin.y < 0 {
            origin.y = point.y + 16
        }
        _ = drawChip(text, at: origin, fill: Self.yellow, font: font)
    }

    private func drawHint(in ctx: CGContext) {
        var parts: [String]
        if controller.windowMode {
            parts = ["Click a window", "Space: area", "Esc: cancel"]
        } else {
            parts = ["Drag an area", "Tab: ratio (\(controller.aspectRatio.label))"]
            if controller.aspectRatio != .free {
                parts.append("X: rotate")
            }
            parts.append("Space: window")
            if controller.isLive {
                parts.append("Enter: full screen")
            }
            parts.append("Esc: cancel")
        }
        let text = parts.joined(separator: "   ·   ")
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width + 20
        _ = drawChip(text, at: CGPoint(x: ((bounds.width - width) / 2).rounded(), y: bounds.height - 90), fill: .white, font: font)
    }
}
