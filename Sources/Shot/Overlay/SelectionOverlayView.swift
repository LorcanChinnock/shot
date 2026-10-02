import AppKit
import ShotCore

final class SelectionOverlayView: NSView {
    private let display: OverlayDisplay
    private let index: Int
    private unowned let controller: SelectionOverlayController

    private var pointer: CGPoint?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var isMoving = false
    private var lastDragPoint: CGPoint?

    private static let minimumSize: CGFloat = 4
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
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        pointer = point
        if controller.windowMode {
            return
        }
        dragStart = point
        lastDragPoint = point
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
        } else if event.modifierFlags.contains(.shift) {
            selection = Geometry.square(from: start, to: point)
        } else {
            selection = Geometry.normalized(from: start, to: point)
        }
        lastDragPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if controller.windowMode {
            if let window = controller.hoveredWindow {
                controller.finish(.window(window))
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
        controller.finish(.area(display: index, rect: selection))
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
        case 36, 76:
            if controller.isLive {
                controller.finish(.fullDisplay(index))
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
        if let image = display.image {
            ctx.interpolationQuality = .high
            ctx.draw(image, in: bounds)
        } else {
            ctx.clear(bounds)
        }

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

        guard let pointer, !controller.windowMode else {
            return
        }
        if selection == nil {
            drawCrosshair(at: pointer, in: ctx)
            drawLoupe(at: pointer, in: ctx)
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
        guard let image = display.image else {
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
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: loupe)
    }

    private func drawSizeLabel(for selection: CGRect, near point: CGPoint) {
        let text = "\(Int((selection.width * display.scale).rounded())) × \(Int((selection.height * display.scale).rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        var box = CGRect(x: point.x + 14, y: point.y - size.height - 18, width: size.width + 12, height: size.height + 6)
        if box.maxX > bounds.width {
            box.origin.x = point.x - box.width - 14
        }
        if box.minY < 0 {
            box.origin.y = point.y + 14
        }
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        string.draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3))
    }
}
