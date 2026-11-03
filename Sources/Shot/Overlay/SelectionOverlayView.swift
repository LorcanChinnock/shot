import AppKit
import ShotCore

final class SelectionOverlayView: NSView {
    let display: OverlayDisplay
    private let index: Int
    private unowned let controller: SelectionOverlayController

    private let showMagnifier = Preferences().showMagnifier
    private let showCrosshair = Preferences().showCrosshair
    private let showSizeLabel = Preferences().showSizeLabel
    private var pointer: CGPoint?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var isMoving = false
    private var lastDragPoint: CGPoint?
    private var portrait: Bool?
    /// The selection was made with the arrow keys, so Return takes it and Option-arrows resize it.
    private var isKeyboardSelection = false
    /// What a click on a button of the bar does, with where each was last drawn.
    private enum BarAction: Equatable {
        case target(CaptureTarget)
        case scrolling
        case delay
        case grantAccess
    }
    private var barHits: [(rect: CGRect, action: BarAction)] = []
    /// A press that landed on a button of the bar: its release clicks it, unless it turns into dragging out an area first.
    private var pressedChip: (action: BarAction, point: CGPoint)?
    /// Whether the bar sits at the bottom or top, or is hidden, so it stays off what's being picked.
    private var barPlacement = OverlayBarPlacement.bottom
    /// The button of the bar under the pointer, which shows its name and key.
    private var hoveredChip: BarAction?
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
        // The bar shows only on the screen with the pointer.
        needsDisplay = true
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
        hoveredChip = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointer = point
        let hovered = barHits.first { $0.rect.contains(point) }?.action
        if hovered != hoveredChip {
            hoveredChip = hovered
            needsDisplay = true
        }
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
        pressedChip = barHits.first { $0.rect.contains(point) }.map { ($0.action, point) }
        if controller.target != .area {
            return
        }
        if pressedChip != nil {
            // Held back until the press turns into a drag, so a click on a chip keeps an area made with the arrow keys.
            dragStart = point
            lastDragPoint = point
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
        if let chip = pressedChip {
            // A drag from a chip starts an area there, so what's under the chips can still be picked.
            guard chip.action != .grantAccess, hypot(point.x - start.x, point.y - start.y) >= Self.orientationLockDistance else {
                return
            }
            pressedChip = nil
            portrait = nil
            selection = nil
            isKeyboardSelection = false
        }
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

    private func perform(_ action: BarAction) {
        switch action {
        case let .target(target): controller.setTarget(target)
        case .scrolling: controller.toggleScrolling()
        case .delay: controller.cycleDelay()
        case .grantAccess: controller.grantPageAccess()
        }
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
        if let chip = pressedChip {
            pressedChip = nil
            dragStart = nil
            perform(chip.action)
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

        // A light dim says the screen is frozen without hiding it; only the outside of an area being made dims more.
        let hole = holeRect()
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole {
            dim.addRect(hole)
        }
        ctx.addPath(dim)
        ctx.setFillColor(NSColor.black.withAlphaComponent(controller.target == .area && hole != nil ? 0.35 : 0.1).cgColor)
        ctx.fillPath(using: .evenOdd)

        if let hole {
            switch controller.target {
            case .area:
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(hole.insetBy(dx: 0.5, dy: 0.5))
            case .window, .browser:
                ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.2).cgColor)
                ctx.fill(hole)
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(hole.insetBy(dx: 0.5, dy: 0.5))
            case .screen:
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.setLineWidth(4)
                ctx.stroke(hole.insetBy(dx: 2, dy: 2))
            }
        }

        drawBar(avoiding: hole)
        if controller.needsPageAccess {
            drawAccessCard()
        }
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
        } else if let selection, showSizeLabel {
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

    /// Every key the overlay takes, for VoiceOver's help. The bar shows none of it, only each button's name and key on hover.
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

    /// Explains why Browser can't pick a page yet, with a chip that asks for Accessibility.
    private func drawAccessCard() {
        let textSize = Preferences().textSize
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let title = NSAttributedString(string: String(localized: "Browser capture needs Accessibility"), attributes: [
            .font: NSFont.systemFont(ofSize: textSize.points(18), weight: .heavy), .foregroundColor: NSColor(Brutal.ink), .paragraphStyle: paragraph,
        ])
        let body = NSAttributedString(string: String(localized: "macOS only lets Shot find where a browser shows its page once you allow it. Area, Window and Screen work without it."), attributes: [
            .font: NSFont.systemFont(ofSize: textSize.points(13), weight: .medium), .foregroundColor: NSColor(Brutal.ink).withAlphaComponent(0.75), .paragraphStyle: paragraph,
        ])
        let width: CGFloat = 400
        let inner = width - 48
        let titleHeight = title.boundingRect(with: CGSize(width: inner, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin).height.rounded(.up)
        let bodyHeight = body.boundingRect(with: CGSize(width: inner, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin).height.rounded(.up)
        let buttonFont = NSFont.systemFont(ofSize: textSize.points(13), weight: .bold)
        let buttonHeight = (String("A") as NSString).size(withAttributes: [.font: buttonFont]).height.rounded() + 10
        let height = 24 + titleHeight + 10 + bodyHeight + 18 + buttonHeight + 24
        let card = CGRect(x: ((bounds.width - width) / 2).rounded(), y: ((bounds.height - height) / 2).rounded(), width: width, height: height)
        NSColor(Brutal.line).setFill()
        NSBezierPath(roundedRect: card.offsetBy(dx: 4, dy: -4), xRadius: 12, yRadius: 12).fill()
        NSColor(Brutal.paper).setFill()
        let shape = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        shape.fill()
        NSColor(Brutal.line).setStroke()
        shape.lineWidth = 2
        shape.stroke()
        // Drawing is bottom-up: the button sits at the bottom, then the body, then the title.
        let buttonText = String(localized: "Grant Accessibility")
        let buttonWidth = (buttonText as NSString).size(withAttributes: [.font: buttonFont]).width.rounded() + 20
        let box = drawChip(buttonText, at: CGPoint(x: (card.midX - buttonWidth / 2).rounded(), y: card.minY + 24), yellow: true, font: buttonFont)
        barHits.append((box, .grantAccess))
        body.draw(in: CGRect(x: card.minX + 24, y: box.maxY + 18, width: inner, height: bodyHeight))
        title.draw(in: CGRect(x: card.minX + 24, y: box.maxY + 18 + bodyHeight + 10, width: inner, height: titleHeight))
    }

    /// One button of the bar: a mode, Scroll or Delay. `label` is shown beside the icon only while it's picked or on.
    private struct BarButton {
        let symbol: String
        let label: String?
        let on: Bool
        let tip: String
        let action: BarAction
    }

    private var barButtons: (modes: [BarButton], options: [BarButton]) {
        let symbols: [CaptureTarget: String] = [.area: "rectangle.dashed", .window: "macwindow", .browser: "safari", .screen: "display"]
        let modes = CaptureTarget.allCases.map { target in
            let picked = target == controller.target
            return BarButton(symbol: symbols[target] ?? "rectangle.dashed", label: picked ? target.title : nil, on: picked, tip: "\(target.title)  ·  Tab", action: .target(target))
        }
        var options: [BarButton] = []
        if controller.offersScrolling {
            let scroll = String(localized: "Scroll")
            options.append(BarButton(symbol: "arrow.down.to.line", label: controller.scrolling ? scroll : nil, on: controller.scrolling, tip: "\(scroll)  ·  S", action: .scrolling))
        }
        if controller.offersDelay {
            let delay = controller.delay
            options.append(BarButton(
                symbol: "timer", label: delay > 0 ? CaptureDelay.label(delay) : nil, on: delay > 0,
                tip: "\(String(localized: "Delay: \(CaptureDelay.label(delay))"))  ·  D", action: .delay
            ))
        }
        return (modes, options)
    }

    /// A small bar of icons that pick area, window, browser or full screen, then Scroll and Delay; a click does what Tab, S and D do.
    /// It shows on the screen with the pointer only, at the bottom unless what's being picked reaches it, and hides while an area is dragged out.
    private func drawBar(avoiding hole: CGRect?) {
        let previous = barHits.map(\.rect)
        barHits = []
        guard let window, NSMouseInRect(NSEvent.mouseLocation, window.frame, false) else {
            return
        }
        let textSize = Preferences().textSize
        let font = NSFont.systemFont(ofSize: textSize.points(13), weight: .bold)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: textSize.points(14), weight: .bold)
        let (modes, options) = barButtons
        let pad: CGFloat = 4
        let gap: CGFloat = 2
        let divider: CGFloat = 14
        let height = (String("A") as NSString).size(withAttributes: [.font: font]).height.rounded() + 14

        func icon(_ button: BarButton, color: NSColor = .black) -> NSImage? {
            NSImage(systemSymbolName: button.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig.applying(NSImage.SymbolConfiguration(paletteColors: [color])))
        }
        func width(_ button: BarButton) -> CGFloat {
            let iconWidth = icon(button)?.size.width.rounded(.up) ?? 0
            guard let label = button.label else {
                return max(iconWidth + 20, height)
            }
            return iconWidth + 6 + (label as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 20
        }
        let modeWidths = modes.map(width)
        let optionWidths = options.map(width)
        func span(_ widths: [CGFloat]) -> CGFloat {
            widths.reduce(0, +) + gap * CGFloat(max(widths.count - 1, 0))
        }
        let size = CGSize(
            width: pad * 2 + span(modeWidths) + (options.isEmpty ? 0 : divider + span(optionWidths)),
            height: height + pad * 2
        )

        let dragging = dragStart != nil && pressedChip == nil && !isKeyboardSelection && selection != nil
        barPlacement = OverlayBarPlacement.placement(
            for: size, in: bounds, avoiding: aim(hole), dragging: dragging, current: barPlacement,
            pointerOnBar: dragStart == nil && pointer.map { point in previous.contains { $0.contains(point) } } ?? false
        )
        guard let frame = barPlacement.frame(of: size, in: bounds) else {
            hoveredChip = nil
            return
        }
        NSColor(Brutal.line).setFill()
        NSBezierPath(roundedRect: frame.offsetBy(dx: 3, dy: -3), xRadius: 9, yRadius: 9).fill()
        NSColor(Brutal.paper).setFill()
        let shape = NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9)
        shape.fill()
        NSColor(Brutal.line).setStroke()
        shape.lineWidth = 2
        shape.stroke()

        var x = frame.minX + pad
        var tip: (text: String, box: CGRect)?
        func drawButtons(_ buttons: [BarButton], _ widths: [CGFloat]) {
            for (button, buttonWidth) in zip(buttons, widths) {
                let box = CGRect(x: x, y: frame.minY + pad, width: buttonWidth, height: height)
                let ink = button.on ? Self.ink : NSColor(Brutal.ink)
                if button.on {
                    NSColor(Brutal.yellow).setFill()
                    let fill = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
                    fill.fill()
                    NSColor(Brutal.line).setStroke()
                    fill.lineWidth = 2
                    fill.stroke()
                } else if hoveredChip == button.action {
                    NSColor(Brutal.ink).withAlphaComponent(0.1).setFill()
                    NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
                }
                var contentX = box.minX + 10
                if let image = icon(button, color: ink) {
                    let imageSize = image.size
                    if button.label == nil {
                        contentX = (box.midX - imageSize.width / 2).rounded()
                    }
                    image.draw(in: CGRect(x: contentX, y: (box.midY - imageSize.height / 2).rounded(), width: imageSize.width, height: imageSize.height))
                    contentX += imageSize.width.rounded(.up) + 6
                }
                if let label = button.label {
                    let string = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: ink])
                    string.draw(at: CGPoint(x: contentX, y: (box.midY - string.size().height / 2).rounded()))
                }
                barHits.append((box, button.action))
                if hoveredChip == button.action {
                    tip = (button.tip, box)
                }
                x += buttonWidth + gap
            }
        }
        drawButtons(modes, modeWidths)
        if !options.isEmpty {
            x += divider / 2 - gap
            NSColor(Brutal.line).withAlphaComponent(0.35).setFill()
            NSBezierPath(rect: CGRect(x: x - 1, y: frame.minY + pad + 6, width: 2, height: height - 12)).fill()
            x += divider / 2
            drawButtons(options, optionWidths)
        }
        // The hovered button's name and key, on the side of the bar away from the screen's edge.
        if let tip {
            let tipFont = NSFont.systemFont(ofSize: textSize.points(12), weight: .bold)
            let tipWidth = (tip.text as NSString).size(withAttributes: [.font: tipFont]).width.rounded() + 20
            let tipHeight = (tip.text as NSString).size(withAttributes: [.font: tipFont]).height.rounded() + 10
            let tipX = min(max(tip.box.midX - tipWidth / 2, 8), bounds.width - tipWidth - 8).rounded()
            let tipY = barPlacement == .top ? frame.minY - 10 - tipHeight : frame.maxY + 10
            _ = drawChip(tip.text, at: CGPoint(x: tipX, y: tipY), yellow: false, font: tipFont)
        }
    }

    /// What the bar keeps off: an area made with the arrow keys, or the highlighted window or page. A full screen is picked with a click anywhere.
    private func aim(_ hole: CGRect?) -> OverlayBarPlacement.Aim? {
        guard let hole else {
            return nil
        }
        switch controller.target {
        case .area: return .area(hole)
        case .window, .browser: return .target(hole)
        case .screen: return nil
        }
    }
}
