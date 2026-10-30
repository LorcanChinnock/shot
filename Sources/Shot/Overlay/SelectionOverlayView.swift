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
    /// The selection was made with the arrow keys, so Return takes it and Option-arrows resize it.
    private var isKeyboardSelection = false
    /// What a click on the target, scroll and delay chips does, with where each was last drawn.
    private enum BarAction: Equatable {
        case target(CaptureTarget)
        case scrolling
        case delay
    }
    private var barHits: [(rect: CGRect, action: BarAction)] = []
    /// A press landed on a chip, so its release isn't a click on the screen or window underneath.
    private var pressedBar = false
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
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Capture overlay"))
        setAccessibilityHelp(hintText)
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

    /// Drops a half-made area when Tab or a click changes what the overlay picks.
    func targetChanged() {
        selection = nil
        dragStart = nil
        isMoving = false
        isKeyboardSelection = false
        portrait = nil
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        if controller.windowMode {
            controller.releaseKeyboardWindow()
            controller.updateHover()
        } else {
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        pointer = point
        if let hit = barHits.first(where: { $0.rect.contains(point) }) {
            pressedBar = true
            switch hit.action {
            case let .target(target): controller.setTarget(target)
            case .scrolling: controller.toggleScrolling()
            case .delay: controller.cycleDelay()
            }
            return
        }
        if controller.target != .area {
            return
        }
        dragStart = point
        lastDragPoint = point
        portrait = nil
        selection = nil
        isKeyboardSelection = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard controller.target == .area, let start = dragStart else {
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
        if pressedBar {
            pressedBar = false
            return
        }
        if controller.windowMode {
            if let window = controller.hoveredWindow {
                controller.finish(controller.selection(for: window), modifiers: event.modifierFlags)
            }
            return
        }
        if controller.screenMode {
            controller.finish(.fullDisplay(index), modifiers: event.modifierFlags)
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
        case 48:
            controller.cycleTarget(backward: event.modifierFlags.contains(.shift))
        case 1:
            controller.toggleScrolling()
        case 2:
            controller.cycleDelay()
        case 123...126 where controller.target == .window:
            controller.stepWindow(backward: event.keyCode == 123 || event.keyCode == 126)
        case 123...126 where controller.target == .area && dragStart == nil:
            nudgeSelection(keyCode: event.keyCode, event.modifierFlags)
        case 15 where controller.target == .area:
            controller.aspectRatio = controller.aspectRatio.next(backward: event.modifierFlags.contains(.shift))
            if isKeyboardSelection, let current = selection {
                let ratio = controller.aspectRatio.value.map { current.width >= current.height ? $0 : 1 / $0 }
                selection = KeyboardArea.start(at: CGPoint(x: current.midX, y: current.midY), ratio: ratio, in: bounds)
            }
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
        case 36 where isKeyboardSelection, 76 where isKeyboardSelection:
            if let selection {
                let ratio = controller.aspectRatio.value.map { selection.width >= selection.height ? $0 : 1 / $0 }
                controller.finish(.area(display: index, rect: selection, ratio: ratio), modifiers: event.modifierFlags)
            }
        case 36 where controller.windowMode && controller.hoveredWindow != nil, 76 where controller.windowMode && controller.hoveredWindow != nil:
            if let window = controller.hoveredWindow {
                controller.finish(controller.selection(for: window), modifiers: event.modifierFlags)
            }
        case 36 where controller.screenMode, 76 where controller.screenMode:
            controller.finish(.fullDisplay(index), modifiers: event.modifierFlags)
        default:
            super.keyDown(with: event)
        }
    }

    /// Arrow keys draw and nudge an area without a mouse: the first press makes one at the pointer (a held arrow announces only its first press, so speech does not queue), then arrows move it,
    /// Option-arrows resize it, and Shift takes single points instead of steps.
    private func nudgeSelection(keyCode: UInt16, _ flags: NSEvent.ModifierFlags) {
        let amount = flags.contains(.shift) ? KeyboardArea.fineStep : KeyboardArea.step
        let dx: CGFloat = keyCode == 124 ? amount : keyCode == 123 ? -amount : 0
        let dy: CGFloat = keyCode == 126 ? amount : keyCode == 125 ? -amount : 0
        let ratio = controller.aspectRatio.value
        if isKeyboardSelection, let current = selection {
            if flags.contains(.option) {
                selection = KeyboardArea.resized(current, dw: dx, dh: dy, ratio: ratio, in: bounds)
            } else {
                selection = KeyboardArea.moved(current, dx: dx, dy: dy, in: bounds)
            }
        } else {
            let centre = pointer ?? CGPoint(x: bounds.midX, y: bounds.midY)
            selection = KeyboardArea.start(at: centre, ratio: ratio, in: bounds)
            isKeyboardSelection = true
            announce(String(localized: "Area started. Arrow keys move it, Option and arrow keys resize it, Return captures it."))
        }
        if let selection {
            let size = sizeText(of: selection)
            setAccessibilityValue(size)
            if !(NSApp.currentEvent?.isARepeat ?? false) {
                announce(size)
            }
        }
        needsDisplay = true
    }

    func announceWindow(_ name: String) {
        announce(name.isEmpty ? String(localized: "Window") : name)
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    private func sizeText(of selection: CGRect) -> String {
        "\(Int((selection.width * display.scale).rounded())) × \(Int((selection.height * display.scale).rounded()))"
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
            if controller.target != .area {
                ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.25).cgColor)
                ctx.fill(hole)
            }
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(hole.insetBy(dx: 0.5, dy: 0.5))
        }

        drawHint(in: ctx)
        drawBar()
        guard let pointer, controller.target == .area else {
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
        if controller.screenMode {
            return pointer == nil ? nil : bounds
        }
        if controller.windowMode {
            guard let window = controller.hoveredWindow else {
                return nil
            }
            let global = controller.hoveredPageFrame ?? controller.appKitFrame(of: window)
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

    private static let ink = Brutal.inkNS

    /// Neo-brutalist chip: flat fill, ink border, hard offset shadow. A paper chip follows the appearance; on the yellow accent
    /// the text stays near-black, as `inkOnFill` keeps it in SwiftUI.
    private func drawChip(_ text: String, at origin: CGPoint, yellow: Bool, font: NSFont) -> CGRect {
        let fill = NSColor(yellow ? Brutal.yellow : Brutal.paper)
        let textColor = yellow ? Self.ink : NSColor(Brutal.ink)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
        let size = string.size()
        let box = CGRect(x: origin.x, y: origin.y, width: (size.width + 20).rounded(), height: (size.height + 10).rounded())
        NSColor(Brutal.line).setFill()
        NSBezierPath(roundedRect: box.offsetBy(dx: 3, dy: -3), xRadius: 7, yRadius: 7).fill()
        fill.setFill()
        let shape = NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7)
        shape.fill()
        NSColor(Brutal.line).setStroke()
        shape.lineWidth = 2
        shape.stroke()
        string.draw(at: CGPoint(x: box.minX + 10, y: box.minY + 5))
        return box
    }

    private func drawSizeLabel(for selection: CGRect, near point: CGPoint) {
        var text = sizeText(of: selection)
        if controller.aspectRatio != .free {
            text = "\(controller.aspectRatio.label(portrait: selection.height > selection.width)) · \(text)"
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: Preferences().textSize.points(12), weight: .bold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width + 20
        var origin = CGPoint(x: point.x + 16, y: point.y - 44)
        if origin.x + width > bounds.width {
            origin.x = point.x - width - 16
        }
        if origin.y < 0 {
            origin.y = point.y + 16
        }
        _ = drawChip(text, at: origin, yellow: true, font: font)
    }

    private var hintText: String {
        var parts: [String]
        switch controller.target {
        case .area:
            parts = [String(localized: "Drag an area"), String(localized: "Arrows: move"), String(localized: "R: ratio (\(controller.aspectRatio.label))")]
            if controller.aspectRatio != .free {
                parts.append(String(localized: "X: rotate"))
            }
        case .window:
            parts = [String(localized: "Click a window"), String(localized: "Arrows: next window")]
        case .browser:
            parts = controller.needsPageAccess
                ? [String(localized: "Allow Accessibility in System Settings to pick a page")]
                : [String(localized: "Click a browser page")]
        case .screen:
            parts = [String(localized: "Click a screen")]
        }
        parts.append(String(localized: "Tab: area, window, browser or screen"))
        if controller.offersScrolling {
            parts.append(String(localized: "S: scroll"))
        }
        if controller.offersDelay {
            parts.append(String(localized: "D: delay"))
        }
        parts.append(String(localized: "Esc: cancel"))
        return parts.joined(separator: "   ·   ")
    }

    private func drawHint(in ctx: CGContext) {
        let text = hintText
        let textSize = Preferences().textSize
        let font = NSFont.systemFont(ofSize: textSize.points(13), weight: .bold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width + 20
        _ = drawChip(text, at: CGPoint(x: ((bounds.width - width) / 2).rounded(), y: bounds.height - 90), yellow: false, font: font)
    }

    /// The chips under the hint that pick area, window, browser or full screen, the scroll toggle and the delay. Clicking one does what Tab and D do.
    private func drawBar() {
        let font = NSFont.systemFont(ofSize: Preferences().textSize.points(13), weight: .bold)
        var chips: [(text: String, yellow: Bool, action: BarAction)] = CaptureTarget.allCases.map {
            ($0.title, $0 == controller.target, .target($0))
        }
        if controller.offersScrolling {
            chips.append((String(localized: "Scroll"), controller.scrolling, .scrolling))
        }
        if controller.offersDelay {
            chips.append((String(localized: "Delay: \(CaptureDelay.label(controller.delay))"), controller.delay > 0, .delay))
        }
        let gap: CGFloat = 12
        let widths = chips.map { ($0.text as NSString).size(withAttributes: [.font: font]).width.rounded() + 20 }
        var x = ((bounds.width - widths.reduce(0, +) - gap * CGFloat(chips.count - 1)) / 2).rounded()
        barHits = []
        for (chip, width) in zip(chips, widths) {
            let box = drawChip(chip.text, at: CGPoint(x: x, y: bounds.height - 138), yellow: chip.yellow, font: font)
            barHits.append((box, chip.action))
            x += width + gap
        }
    }
}
