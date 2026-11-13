import AppKit
import ShotCore

final class SelectionOverlayView: NSView {
    let display: OverlayDisplay
    private let index: Int
    private unowned let controller: SelectionOverlayController

    private var showMagnifier: Bool { controller.showMagnifier }
    private var showCrosshair: Bool { controller.showCrosshair }
    private var showSizeLabel: Bool { controller.showSizeLabel }
    /// Whether the pointer is over a button of the bar, which keeps the bar from going.
    var pointerIsOnBar: Bool {
        guard let pointer else {
            return false
        }
        return barHits.contains { $0.rect.contains(pointer) }
    }
    private var pointer: CGPoint?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var isMoving = false
    private var lastDragPoint: CGPoint?
    /// The selection was made with the arrow keys, so Return takes it and Option-arrows resize it.
    private var isKeyboardSelection = false
    /// What a click on a button of the bar does, with where each was last drawn.
    private enum BarAction: Equatable {
        case mode(CaptureBarMode)
        case scrolling
        case delay
        case magnifier
        case crosshair
        case resolution
        case ratio
    }
    private var barHits: [(rect: CGRect, action: BarAction)] = []
    /// A press that landed on a button of the bar: its release clicks it, unless it turns into dragging out an area first.
    private var pressedChip: (action: BarAction, point: CGPoint)?
    /// Whether the bar sits at the bottom or top, or is hidden, so it stays off what's being picked.
    private var barPlacement = OverlayBarPlacement.bottom
    /// Where the bar was last drawn, nil while it's hidden or faded, so the chips and loupe keep off it.
    private var barFrame: CGRect?
    /// The bar's frame in AppKit global space, nil while it's hidden or faded, for the permission card to sit beside.
    var barScreenFrame: CGRect? {
        guard let barFrame, let window else {
            return nil
        }
        return window.convertToScreen(convert(barFrame, to: nil))
    }
    /// Set by a click that closed the permission card, so its release doesn't capture.
    private var swallowsMouseUp = false
    /// Where the bar's tooltip was last drawn, so the window pick's label keeps off it too.
    private var tipFrame: CGRect?
    /// The button of the bar under the pointer, which shows its name and key.
    private var hoveredChip: BarAction?
    var magnifierImage: CGImage? {
        didSet { needsDisplay = true }
    }

    private static let minimumSize: CGFloat = 4
    private static let orientationLockDistance: CGFloat = 8

    init(frame: NSRect, display: OverlayDisplay, index: Int, controller: SelectionOverlayController) {
        self.display = display
        self.index = index
        self.controller = controller
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    /// Read when VoiceOver asks, so they follow the mode, ratio and kind as they change. The kind leads the label, since
    /// the bar only draws it.
    override func accessibilityLabel() -> String? {
        controller.recording ? String(localized: "Record overlay") : String(localized: "Screenshot overlay")
    }

    override func accessibilityHelp() -> String? {
        hintText
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
        // The bar shows only on the screen with the pointer.
        needsDisplay = true
    }

    /// Drops a half-made area when Tab or a click changes what the overlay picks.
    func targetChanged() {
        selection = nil
        dragStart = nil
        isMoving = false
        isKeyboardSelection = false
        setAccessibilityValue(nil)
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
        if hovered != nil {
            controller.revealBar()
        }
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
        // A click beside the permission card closes it, like a popover, rather than capturing.
        if controller.showsPermissionCard {
            controller.closePermissionCard()
            swallowsMouseUp = true
            return
        }
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
            guard hypot(point.x - start.x, point.y - start.y) >= Self.orientationLockDistance else {
                return
            }
            pressedChip = nil
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
            selection = shaped(from: start, to: point)
        }
        lastDragPoint = point
        needsDisplay = true
    }

    private func perform(_ action: BarAction) {
        switch action {
        case let .mode(mode): controller.setMode(mode)
        case .scrolling: controller.toggleScrolling()
        case .delay: controller.cycleDelay()
        case .magnifier: controller.toggleMagnifier()
        case .crosshair: controller.toggleCrosshair()
        case .resolution: controller.toggleSizeLabel()
        case .ratio: showRatioMenu()
        }
    }

    private func shaped(from start: CGPoint, to point: CGPoint) -> CGRect {
        if let ratio = controller.areaShape.widthOverHeight {
            return Geometry.fitted(from: start, to: point, ratio: ratio, in: bounds)
        }
        return Geometry.normalized(from: start, to: point)
    }

    /// The Ratio button's menu: the ratios, as they'd be turned now, then Turn. A native menu, so it reads and works like any other.
    private func showRatioMenu() {
        guard let box = barHits.first(where: { $0.action == .ratio })?.rect else {
            return
        }
        let shape = controller.areaShape
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, ratio) in AspectRatio.allCases.enumerated() {
            let title = AreaShape(ratio: ratio, portrait: shape.portrait).label
            let item = NSMenuItem(title: title, action: #selector(pickRatio(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = ratio == shape.ratio ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let turn = NSMenuItem(
            title: shape.portrait ? String(localized: "Turn to Landscape") : String(localized: "Turn to Portrait"),
            action: #selector(turnRatio), keyEquivalent: "x"
        )
        turn.keyEquivalentModifierMask = []
        turn.target = self
        turn.isEnabled = shape.turns
        menu.addItem(turn)
        // Clear of the bar, on the side away from the screen's edge, so every item shows without scrolling.
        let gap: CGFloat = 6
        let top = barPlacement == .top ? box.minY - gap : box.maxY + gap + menu.size.height
        // The button's tooltip would show under the menu.
        hoveredChip = nil
        display()
        menu.popUp(positioning: nil, at: CGPoint(x: box.minX, y: top), in: self)
        controller.revealBar()
    }

    @objc private func pickRatio(_ sender: NSMenuItem) {
        setShape { $0.ratio = AspectRatio.allCases[sender.tag] }
    }

    @objc private func turnRatio() {
        setShape { $0.turn() }
    }

    /// Changes the ratio or its turn, reshapes an area being made to match, and says what it now is.
    private func setShape(_ change: (inout AreaShape) -> Void) {
        var shape = controller.areaShape
        change(&shape)
        controller.areaShape = shape
        if isKeyboardSelection, let current = selection {
            selection = KeyboardArea.start(at: CGPoint(x: current.midX, y: current.midY), ratio: shape.widthOverHeight, in: bounds)
        }
        if let start = dragStart, let point = lastDragPoint, !isMoving, pressedChip == nil {
            selection = shaped(from: start, to: point)
        }
        announce(String(localized: "Ratio: \(shape.label)"))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if swallowsMouseUp {
            swallowsMouseUp = false
            return
        }
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
        controller.finish(.area(display: index, rect: selection, ratio: controller.areaShape.widthOverHeight), modifiers: event.modifierFlags)
    }

    override func keyDown(with event: NSEvent) {
        if [49, 48, 1, 2, 46, 8, 34, 11, 15, 7].contains(event.keyCode), !event.isARepeat {
            controller.revealBar()
        }
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
        case 46:
            controller.toggleMagnifier()
        case 8:
            controller.toggleCrosshair()
        case 34:
            controller.toggleSizeLabel()
        case 11:
            controller.togglePageOnly()
        case 123...126 where controller.target == .window:
            controller.stepWindow(backward: event.keyCode == 123 || event.keyCode == 126)
        case 123...126 where controller.target == .area && dragStart == nil:
            nudgeSelection(keyCode: event.keyCode, event.modifierFlags)
        case 15 where controller.target == .area:
            let backward = event.modifierFlags.contains(.shift)
            setShape { $0.ratio = $0.ratio.next(backward: backward) }
        case 7 where controller.target == .area && controller.areaShape.turns:
            setShape { $0.turn() }
        case 36 where isKeyboardSelection, 76 where isKeyboardSelection:
            if let selection {
                controller.finish(.area(display: index, rect: selection, ratio: controller.areaShape.widthOverHeight), modifiers: event.modifierFlags)
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
        let shape = controller.areaShape
        if isKeyboardSelection, let current = selection {
            if flags.contains(.option) {
                selection = KeyboardArea.resized(current, dw: dx, dh: dy, ratio: shape.ratio.value, in: bounds)
            } else {
                selection = KeyboardArea.moved(current, dx: dx, dy: dy, in: bounds)
            }
        } else {
            let centre = pointer ?? CGPoint(x: bounds.midX, y: bounds.midY)
            selection = KeyboardArea.start(at: centre, ratio: shape.widthOverHeight, in: bounds)
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

    /// Reads out the window stepped to with the arrow keys: its name and size, as its label shows them.
    func announceWindow() {
        if let details = pickDetails {
            announce("\(details.name), \(details.size)")
        }
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

        // A light dim says the screen is frozen without hiding it; only the outside of an area being made or a highlighted
        // window dims more.
        let hole = holeRect()
        // A whole window keeps rounded corners like the window's own. A page and a screen are square.
        let radius = controller.target == .window && controller.hoveredPageFrame == nil ? Theme.Radius.panel : 0
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole {
            dim.addPath(Self.roundedPath(hole, radius: radius))
        }
        ctx.addPath(dim)
        let dimColor = switch controller.target {
        case .area where hole != nil: Self.areaDim
        case .window where hole != nil: Self.pickDim
        default: NSColor.black.withAlphaComponent(0.1).cgColor
        }
        ctx.setFillColor(dimColor)
        ctx.fillPath(using: .evenOdd)

        if let hole {
            switch controller.target {
            case .area: drawAreaEdge(hole, in: ctx)
            case .window, .screen: drawPickHighlight(hole, radius: radius, in: ctx)
            }
        }

        drawBar(avoiding: hole)
        if let hole, controller.target != .area {
            drawPickLabel(in: hole, in: ctx)
        }
        guard controller.target == .area else {
            return
        }
        let avoiding = barFrame.map { [$0.insetBy(dx: -8, dy: -8)] } ?? []
        let chips = selection.flatMap { drawChips(for: $0, avoiding: avoiding, in: ctx) }
        // The guides and loupe follow the pointer before and while dragging, but not for an area made with the arrow keys,
        // whose edges are elsewhere. Over the bar, they'd cover the buttons and their tooltip.
        let dragging = dragStart != nil && selection != nil && !isKeyboardSelection
        guard let pointer, selection == nil || dragging, !pointerIsOnBar else {
            return
        }
        if showCrosshair {
            drawGuides(at: pointer, in: ctx)
        }
        if showMagnifier {
            // Away from the area, so it doesn't cover the edges being placed: below and right of the pointer to begin with.
            let start = dragging ? dragStart : nil
            let right = start.map { pointer.x >= $0.x } ?? true
            let up = start.map { pointer.y > $0.y } ?? false
            drawLoupe(at: pointer, right: right, up: up, avoiding: avoiding + (chips.map { [$0] } ?? []), in: ctx)
        }
    }

    /// Outside an area being made: `rgba(12,12,16,0.42)`, from the board.
    private static let areaDim = CGColor(srgbRed: 12 / 255, green: 12 / 255, blue: 16 / 255, alpha: 0.42)

    /// The area's edge from the board: a 1 pt white line just outside it, a 1 pt dark ring outside that, so it shows on light
    /// and dark screens alike, and a round white handle with an ink edge at each corner and the middle of each long side.
    private func drawAreaEdge(_ area: CGRect, in ctx: CGContext) {
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.stroke(area.insetBy(dx: -1.5, dy: -1.5))
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        ctx.stroke(area.insetBy(dx: -0.5, dy: -0.5))
        let scale = window?.backingScaleFactor ?? 2
        let edge = Theme.inkWidth(1.5, scale: scale)
        let radius = AreaHandles.diameter / 2
        ctx.setLineWidth(edge)
        ctx.setStrokeColor(Self.ink.cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        for point in AreaHandles.points(around: area) {
            let handle = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            ctx.fillEllipse(in: handle)
            ctx.strokeEllipse(in: handle.insetBy(dx: -edge / 2, dy: -edge / 2))
        }
    }

    // MARK: Window pick

    /// Outside a highlighted window or page: `rgba(12,12,16,0.34)`, from the board.
    private static let pickDim = CGColor(srgbRed: 12 / 255, green: 12 / 255, blue: 16 / 255, alpha: 0.34)

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let corner = max(min(radius, rect.width / 2, rect.height / 2), 0)
        return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }

    /// The board's highlight on the window, page or screen a click would capture: the accent at 16% over it, a 3 pt accent
    /// ring just inside its edge and a 1.5 pt ink ring inside that, so it shows on light and dark windows alike.
    private func drawPickHighlight(_ hole: CGRect, radius: CGFloat, in ctx: CGContext) {
        let ink = Theme.inkWidth(1.5, scale: window?.backingScaleFactor ?? 2)
        let ring: CGFloat = 3
        func path(_ inset: CGFloat) -> CGPath {
            Self.roundedPath(hole.insetBy(dx: inset, dy: inset), radius: radius - inset)
        }
        ctx.addPath(path(0))
        ctx.setFillColor(Theme.yellowNS.withAlphaComponent(0.16).cgColor)
        ctx.fillPath()
        guard hole.width > (ring + ink) * 2, hole.height > (ring + ink) * 2 else {
            return
        }
        ctx.addPath(path(0))
        ctx.addPath(path(ring))
        ctx.setFillColor(Theme.yellowNS.cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.addPath(path(ring))
        ctx.addPath(path(ring + ink))
        ctx.setFillColor(Self.ink.cgColor)
        ctx.fillPath(using: .evenOdd)
    }

    /// What the label names: the window or screen, its size in pixels as the image will be, and whether the window's shadow
    /// comes with it. Nil when nothing is highlighted.
    private var pickDetails: (name: String, size: String, shadow: Bool)? {
        if controller.screenMode {
            let name = NSScreen.screens.first { $0.frame == display.frame }?.localizedName ?? String(localized: "Screen")
            return (name, sizeText(of: bounds), false)
        }
        guard let window = controller.hoveredWindow else {
            return nil
        }
        let page = controller.hoveredPageFrame
        let frame = page ?? controller.appKitFrame(of: window)
        return (window.pickName ?? String(localized: "Window"), sizeText(of: frame), page == nil && Preferences().windowShadow)
    }

    /// The board's label in the middle of what's highlighted: a camera on a dark disc, the name and size on a dark panel, and
    /// how to capture it on a light pill. A small window shows fewer parts, and the label keeps off the bar and its tooltip.
    private func drawPickLabel(in hole: CGRect, in ctx: CGContext) {
        guard let details = pickDetails else {
            return
        }
        let textSize = Preferences().textSize
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let name = NSAttributedString(string: details.name, attributes: [
            .font: NSFont.systemFont(ofSize: textSize.points(13), weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: truncating,
        ])
        let sizeLine = details.shadow ? String(localized: "\(details.size) · with shadow") : details.size
        let size = NSAttributedString(string: sizeLine, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: textSize.points(11.5), weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(increased ? 1 : 0.75),
        ])
        let hintLine = controller.windowMode
            ? [String(localized: "Click or press Return to capture"), String(localized: "Arrows: next window")].joined(separator: " · ")
            : String(localized: "Click or press Return to capture")
        let hint = NSAttributedString(string: hintLine, attributes: [
            .font: NSFont.systemFont(ofSize: textSize.points(12)), .foregroundColor: Self.ink,
        ])

        // A long title is cut short rather than running past the window.
        let maxName = min(textSize.points(420), max(hole.width - 2 * WindowPickLabel.inset - 28, 80))
        let nameSize = CGSize(width: min(name.size().width.rounded(.up), maxName), height: name.size().height.rounded(.up))
        let sizeSize = CGSize(width: size.size().width.rounded(.up), height: size.size().height.rounded(.up))
        let panel = CGSize(width: max(nameSize.width, sizeSize.width) + 28, height: nameSize.height + 2 + sizeSize.height + 16)
        let hintText = hint.size()
        let pill = CGSize(width: hintText.width.rounded(.up) + 20, height: hintText.height.rounded(.up) + 6)
        let disc = textSize.points(64).rounded()
        var avoiding = barFrame.map { [$0.insetBy(dx: -8, dy: -8)] } ?? []
        if let tipFrame {
            avoiding.append(tipFrame)
        }
        let parts = WindowPickLabel.layout(
            icon: CGSize(width: disc, height: disc), name: panel, hint: pill, spacing: textSize.points(10).rounded(),
            target: hole, in: bounds, avoiding: avoiding
        )
        for (part, frame) in parts {
            switch part {
            case .icon:
                drawPanel(frame, radius: frame.height / 2, opacity: FloatingPanel.Opacity.standard, shadow: true, increased: increased, in: ctx)
                let config = NSImage.SymbolConfiguration(pointSize: textSize.points(24), weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
                if let camera = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                    let s = camera.size
                    camera.draw(in: CGRect(x: (frame.midX - s.width / 2).rounded(), y: (frame.midY - s.height / 2).rounded(), width: s.width, height: s.height))
                }
            case .name:
                drawPanel(frame, radius: Theme.Radius.panel, opacity: FloatingPanel.Opacity.standard, shadow: false, increased: increased, in: ctx)
                let nameRect = CGRect(x: (frame.midX - nameSize.width / 2).rounded(), y: frame.maxY - 8 - nameSize.height, width: nameSize.width, height: nameSize.height)
                name.draw(with: nameRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
                size.draw(at: CGPoint(x: (frame.midX - sizeSize.width / 2).rounded(), y: nameRect.minY - 2 - sizeSize.height))
            case .hint:
                let shape = NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2)
                NSColor.white.withAlphaComponent(FloatingPanel.solidNS ? 1 : 0.9).setFill()
                shape.fill()
                if increased {
                    Self.ink.withAlphaComponent(0.4).setStroke()
                    shape.lineWidth = 1
                    shape.stroke()
                }
                hint.draw(at: CGPoint(x: frame.minX + 10, y: (frame.midY - hintText.height / 2).rounded()))
            }
        }
        let spoken = "\(details.name), \(details.size)"
        if accessibilityValue() as? String != spoken {
            setAccessibilityValue(spoken)
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

    /// The crosshair toggle's guides across the screen, in the area edge's white over a faint dark line so they show on any
    /// screen. They stop short of the pointer, so the cursor's own crosshair stays clear.
    private func drawGuides(at point: CGPoint, in ctx: CGContext) {
        let x = point.x.rounded() + 0.5
        let y = point.y.rounded() + 0.5
        let gap = Self.cursorSide / 2 + 3
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: x - gap, y: y))
        ctx.move(to: CGPoint(x: x + gap, y: y))
        ctx.addLine(to: CGPoint(x: bounds.width, y: y))
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: y - gap))
        ctx.move(to: CGPoint(x: x, y: y + gap))
        ctx.addLine(to: CGPoint(x: x, y: bounds.height))
        guard let path = ctx.path else {
            return
        }
        ctx.setLineWidth(3)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.strokePath()
    }

    /// The board's loupe: the pixels round the pointer, one per cell of an 11 × 11 grid, in a 132 pt circle with a 3 pt white
    /// ring, a 1.5 pt ink ring and a soft shadow. The pointer's row and column are lit in the accent, its pixel is outlined
    /// in ink, and a chip at the bottom gives its position in pixels, as the size chip gives the area's size.
    private func drawLoupe(at point: CGPoint, right: Bool, up: Bool, avoiding: [CGRect], in ctx: CGContext) {
        guard let image = display.image ?? magnifierImage else {
            return
        }
        let textSize = Preferences().textSize
        let scale = window?.backingScaleFactor ?? 2
        let side = textSize.points(Loupe.side).rounded()
        let inkRing = Theme.inkWidth(1.5, scale: scale)
        let outset = 3 + inkRing
        let loupe = Loupe.frame(side: side, outset: outset, at: point, right: right, up: up, in: bounds, avoiding: avoiding)
        let imageSize = CGSize(width: image.width, height: image.height)
        let pixel = Loupe.pixel(at: point, viewHeight: bounds.height, scale: display.scale, imageSize: imageSize)

        // The rings, with the shadow under the outer one.
        ctx.saveGState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.shadowBlurRadius = 14
        shadow.set()
        ctx.setFillColor(Self.ink.cgColor)
        ctx.fillEllipse(in: loupe.insetBy(dx: -outset, dy: -outset))
        ctx.restoreGState()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: loupe.insetBy(dx: -3, dy: -3))

        ctx.saveGState()
        ctx.addEllipse(in: loupe)
        ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(loupe)
        if let placed = Loupe.destination(of: Loupe.source(around: pixel), imageSize: imageSize, in: loupe),
           let crop = image.cropping(to: placed.crop) {
            ctx.interpolationQuality = .none
            ctx.draw(crop, in: placed.rect)
        }
        let cell = side / CGFloat(Loupe.cells)
        let middle = CGFloat(Loupe.cells / 2)
        let centre = CGRect(x: loupe.minX + middle * cell, y: loupe.minY + middle * cell, width: cell, height: cell)
        // The board's grid is ink at 7%, which vanishes over dark pixels, so it's mid-grey to show over both.
        ctx.setFillColor(NSColor(white: 0.5, alpha: 0.3).cgColor)
        let hairline = 1 / scale
        for step in 1..<Loupe.cells {
            let offset = CGFloat(step) * cell
            ctx.fill(CGRect(x: loupe.minX + offset - hairline / 2, y: loupe.minY, width: hairline, height: side))
            ctx.fill(CGRect(x: loupe.minX, y: loupe.minY + offset - hairline / 2, width: side, height: hairline))
        }
        // The row and column lit, leaving the pointer's own pixel its true colour.
        ctx.setFillColor(Theme.yellowNS.withAlphaComponent(0.35).cgColor)
        ctx.fill([
            CGRect(x: centre.minX, y: loupe.minY, width: cell, height: centre.minY - loupe.minY),
            CGRect(x: centre.minX, y: centre.maxY, width: cell, height: loupe.maxY - centre.maxY),
            CGRect(x: loupe.minX, y: centre.minY, width: centre.minX - loupe.minX, height: cell),
            CGRect(x: centre.maxX, y: centre.minY, width: loupe.maxX - centre.maxX, height: cell),
        ])
        // The board's ink outline, with a hairline of white outside it so it still shows over a dark pixel.
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(hairline)
        ctx.stroke(centre.insetBy(dx: -hairline / 2, dy: -hairline / 2))
        ctx.setStrokeColor(Self.ink.cgColor)
        ctx.setLineWidth(inkRing)
        ctx.stroke(centre.insetBy(dx: inkRing / 2, dy: inkRing / 2))

        let position = NSAttributedString(string: "\(pixel.x), \(pixel.y)", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: textSize.points(10), weight: .medium), .foregroundColor: NSColor.white,
        ])
        let size = position.size()
        let chip = CGRect(
            x: (loupe.midX - size.width / 2 - 6).rounded(), y: loupe.minY + 10,
            width: size.width.rounded(.up) + 12, height: size.height.rounded(.up) + 2
        )
        FloatingPanel.fillNS(Self.chipOpacity, solid: FloatingPanel.solidNS).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
        position.draw(at: CGPoint(x: chip.minX + 6, y: chip.minY + 1))
        ctx.restoreGState()
    }

    private static let ink = Theme.inkNS
    /// The capture bar is too tall for a pill, so it has its own radius.
    private static let barRadius: CGFloat = 16
    /// The size, ratio and loupe position chips are a touch more solid than the bar, as the board draws them.
    private static let chipOpacity = 0.88

    /// The board's crosshair cursor: white 3 pt lines under ink 1.2 pt ones, with a gap where they'd meet so the pixel under
    /// the hot spot shows. It replaces the system crosshair, which is thin black and gets lost on dark screens.
    static let cursor: NSCursor = {
        let side = cursorSide
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let mid = side / 2
            let path = NSBezierPath()
            for (from, to) in [(0, mid - 2), (mid + 2, side)] {
                path.move(to: NSPoint(x: mid, y: from))
                path.line(to: NSPoint(x: mid, y: to))
                path.move(to: NSPoint(x: from, y: mid))
                path.line(to: NSPoint(x: to, y: mid))
            }
            path.lineWidth = 3
            NSColor.white.setStroke()
            path.stroke()
            path.lineWidth = 1.2
            Theme.inkNS.setStroke()
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
    }()

    private static let cursorSide: CGFloat = 18

    /// The size chip and, beside it, the ratio chip, above the area's top-left corner. The size is in pixels, as the image
    /// will be, in bold SF Mono so it doesn't jitter while dragging. Size (I) shows both; a ratio other than Free shows on
    /// its own even with Size off, since it changes what you get, and says X turns it, since the bar is hidden while
    /// dragging. Returns where they went, for the loupe to keep off.
    private func drawChips(for area: CGRect, avoiding: [CGRect], in ctx: CGContext) -> CGRect? {
        let shape = controller.areaShape
        guard showSizeLabel || shape.ratio != .free else {
            return nil
        }
        let textSize = Preferences().textSize
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        var texts: [NSAttributedString] = []
        if showSizeLabel {
            texts.append(NSAttributedString(string: sizeText(of: area), attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: textSize.points(12), weight: .bold), .foregroundColor: NSColor.white,
            ]))
        }
        let ratioText = switch shape.ratio {
        case .free: String(localized: "Free ratio")
        case _ where shape.turns: String(localized: "\(shape.label) · X turns")
        default: shape.label
        }
        texts.append(NSAttributedString(string: ratioText, attributes: [
            .font: NSFont.systemFont(ofSize: textSize.points(12), weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(increased ? 1 : 0.75),
        ]))
        let sizes = texts.map { text in
            let size = text.size()
            return CGSize(width: size.width.rounded(.up) + 18, height: size.height.rounded(.up) + 6)
        }
        let spacing: CGFloat = 6
        let height = sizes.map(\.height).max() ?? 0
        let total = CGSize(width: sizes.map(\.width).reduce(0, +) + spacing * CGFloat(sizes.count - 1), height: height)
        let frame = AreaLabelPlacement.frame(of: total, for: area, in: bounds, avoiding: avoiding)
        var x = frame.minX
        for (text, size) in zip(texts, sizes) {
            let chip = CGRect(x: x, y: frame.minY, width: size.width, height: height)
            drawPanel(chip, radius: 8, opacity: Self.chipOpacity, shadow: false, increased: increased, in: ctx)
            text.draw(at: CGPoint(x: chip.minX + 9, y: (chip.midY - text.size().height / 2).rounded()))
            x = chip.maxX + spacing
        }
        return frame
    }

    /// Every key the overlay takes, for VoiceOver's help. The bar shows none of it, only each button's name and key on hover.
    private var hintText: String {
        var parts: [String]
        switch controller.target {
        case .area:
            parts = [String(localized: "Drag an area"), String(localized: "Arrows: move"), String(localized: "R: ratio (\(controller.areaShape.label))")]
            if controller.areaShape.turns {
                parts.append(String(localized: "X: turn"))
            }
        case .window:
            parts = [String(localized: "Click a window"), String(localized: "Arrows: next window")]
        case .screen:
            parts = [String(localized: "Click a screen")]
        }
        parts.append(String(localized: "Tab: area, window or screen"))
        parts.append(String(localized: "B: browser page only"))
        if controller.offersScrolling {
            parts.append(String(localized: "S: scroll"))
        }
        parts.append(String(localized: "M: magnifier"))
        parts.append(String(localized: "C: crosshair"))
        parts.append(String(localized: "I: size"))
        if controller.offersDelay {
            parts.append(String(localized: "D: delay"))
        }
        parts.append(String(localized: "Esc: cancel"))
        return parts.joined(separator: "   ·   ")
    }

    /// One button of the bar. `label` shows beside the icon: the picked mode's name, Scroll, or the delay while it's on.
    private struct BarButton {
        enum Look {
            /// The picked mode: the one ink control on the overlay.
            case picked
            /// A mode that isn't picked, Delay or Scroll: icon at 82% white, a 16% fill while on.
            case plain
            /// The magnifier, crosshair and size toggles: icon at 55% white while off.
            case toggle
        }
        let symbol: String
        /// Drawn in place of `symbol`: a rectangle of this width over height, for the Ratio button.
        var shape: CGFloat?
        let label: String?
        let on: Bool
        let look: Look
        /// The name in its tooltip and for VoiceOver, and the key that does the same.
        let name: String
        let key: String
        let action: BarAction
    }

    /// The bar's buttons in their three groups: the modes, then Delay and Scroll, then the toggles.
    private var barGroups: [[BarButton]] {
        let picked = controller.barMode
        let modes = CaptureBarMode.allCases.map { mode in
            BarButton(
                symbol: Self.symbol(of: mode), label: mode == picked ? mode.title : nil, on: mode == picked,
                look: mode == picked ? .picked : .plain, name: mode.title, key: mode.key, action: .mode(mode)
            )
        }
        var options: [BarButton] = []
        if controller.offersDelay {
            let delay = controller.delay
            options.append(BarButton(
                symbol: "timer", label: delay > 0 ? CaptureDelay.label(delay) : nil, on: delay > 0, look: .plain,
                name: String(localized: "Delay: \(CaptureDelay.label(delay))"), key: "D", action: .delay
            ))
        }
        if controller.offersScrolling {
            let scroll = String(localized: "Scroll")
            options.append(BarButton(symbol: "arrow.down.to.line", label: scroll, on: controller.scrolling, look: .plain, name: scroll, key: "S", action: .scrolling))
        }
        if controller.target == .area {
            let shape = controller.areaShape
            options.append(BarButton(
                symbol: "aspectratio", shape: shape.widthOverHeight, label: shape.ratio == .free ? nil : shape.label, on: shape.ratio != .free,
                look: .plain, name: String(localized: "Ratio: \(shape.label)"), key: "R", action: .ratio
            ))
        }
        func toggle(_ symbol: String, _ name: String, _ key: String, on: Bool, _ action: BarAction) -> BarButton {
            BarButton(symbol: symbol, label: nil, on: on, look: .toggle, name: name, key: key, action: action)
        }
        let aids = [
            toggle("plus.magnifyingglass", String(localized: "Magnifier"), "M", on: controller.showMagnifier, .magnifier),
            toggle("plus", String(localized: "Crosshair"), "C", on: controller.showCrosshair, .crosshair),
            toggle("ruler", String(localized: "Size"), "I", on: controller.showSizeLabel, .resolution),
        ]
        return [modes, options, aids]
    }

    private static func symbol(of mode: CaptureBarMode) -> String {
        switch mode {
        case .area: "viewfinder"
        case .window: "macwindow"
        case .screen: "display"
        case .browser: "globe"
        }
    }

    /// The capture bar (Foundations › Capture bar): whether this is a screenshot or a recording, the four modes, then Delay
    /// and Scroll, then the magnifier, crosshair and size toggles. A click does what Tab, B, D, S, M, C and I do. It shows on
    /// the screen with the pointer only, at the bottom unless what's being picked reaches it, and hides while an area is dragged out.
    private func drawBar(avoiding hole: CGRect?) {
        let previous = barHits.map(\.rect)
        barHits = []
        barFrame = nil
        tipFrame = nil
        let opacity = controller.barOpacity
        guard opacity > 0, let window, NSMouseInRect(NSEvent.mouseLocation, window.frame, false),
              let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }
        let textSize = Preferences().textSize
        let scale = window.backingScaleFactor
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let modeFont = NSFont.systemFont(ofSize: textSize.points(13), weight: .semibold)
        // Delay's seconds tick, so they take tabular figures.
        let optionFont = NSFont.monospacedDigitSystemFont(ofSize: textSize.points(12), weight: .semibold)
        let kindFont = NSFont.systemFont(ofSize: textSize.points(12), weight: .semibold)
        let symbolSize = textSize.points(14)
        let height = textSize.points(34).rounded()
        let groups = barGroups

        func icon(_ button: BarButton, _ color: NSColor) -> NSImage? {
            if let shape = button.shape {
                return Self.ratioIcon(shape, side: symbolSize, color: color)
            }
            let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: button.look == .picked ? .semibold : .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            return NSImage(systemSymbolName: button.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
        func font(_ button: BarButton) -> NSFont {
            button.look == .picked ? modeFont : optionFont
        }
        func width(_ button: BarButton) -> CGFloat {
            guard let label = button.label else {
                // Icon only: a mode is a little wider than tall, and a toggle or Delay is square.
                return button.look == .toggle || button.action == .delay || button.action == .ratio ? height : textSize.points(38).rounded()
            }
            let iconWidth = icon(button, .white)?.size.width.rounded(.up) ?? 0
            let labelWidth = (label as NSString).size(withAttributes: [.font: font(button)]).width.rounded(.up)
            // The board pads the picked mode 10 before its icon and 12 after its name, and Delay and Scroll 10 either side.
            let trailing: CGFloat = button.look == .picked ? 12 : 10
            let spacing: CGFloat = button.look == .picked ? 7 : 6
            return 10 + iconWidth + spacing + labelWidth + trailing
        }

        let kind = controller.recording ? String(localized: "Record") : String(localized: "Screenshot")
        let kindText = NSAttributedString(string: kind, attributes: [
            .font: kindFont, .foregroundColor: NSColor.white.withAlphaComponent(increased ? 1 : 0.8),
        ])
        let dot: CGFloat = 8
        let kindWidth = 8 + dot + 7 + kindText.size().width.rounded(.up) + 10
        let widths = groups.map { $0.map(width) }
        let layout = CaptureBarLayout(groups: [[kindWidth] + widths[0]] + widths.dropFirst(), height: height)
        let size = layout.size

        let dragging = dragStart != nil && pressedChip == nil && !isKeyboardSelection && selection != nil
        let visible = window.screen.map { $0.visibleFrame.offsetBy(dx: -$0.frame.minX, dy: -$0.frame.minY) } ?? bounds
        barPlacement = OverlayBarPlacement.placement(
            for: size, visible: visible, avoiding: aim(hole), dragging: dragging, current: barPlacement,
            pointerOnBar: dragStart == nil && pointer.map { point in previous.contains { $0.contains(point) } } ?? false
        )
        guard let frame = barPlacement.frame(of: size, visible: visible) else {
            hoveredChip = nil
            return
        }
        barFrame = frame
        // While fading, the bar draws into one layer so its shadow and fill fade together rather than showing through each other.
        if opacity < 1 {
            ctx.saveGState()
            ctx.setAlpha(opacity)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer {
            if opacity < 1 {
                ctx.endTransparencyLayer()
                ctx.restoreGState()
            }
        }
        drawPanel(frame, radius: min(Self.barRadius, frame.height / 2), opacity: FloatingPanel.Opacity.standard, shadow: true, increased: increased, in: ctx)

        func placed(_ rect: CGRect) -> CGRect {
            rect.offsetBy(dx: frame.minX, dy: frame.minY)
        }
        // The kind: a dot in the accent for a screenshot or record red for a recording, then its name.
        let kindBox = placed(layout.frames[0][0])
        (controller.recording ? FloatingPanel.recordNS : FloatingPanel.accentNS).setFill()
        NSBezierPath(ovalIn: CGRect(x: kindBox.minX + 8, y: (kindBox.midY - dot / 2).rounded(), width: dot, height: dot)).fill()
        kindText.draw(at: CGPoint(x: kindBox.minX + 8 + dot + 7, y: (kindBox.midY - kindText.size().height / 2).rounded()))

        var tip: (button: BarButton, box: CGRect)?
        let rows = [Array(layout.frames[0].dropFirst())] + layout.frames.dropFirst()
        for (buttons, rects) in zip(groups.filter { !$0.isEmpty }, rows) {
            for (button, rect) in zip(buttons, rects) {
                let box = placed(rect)
                drawButton(button, in: box, hovered: hoveredChip == button.action, increased: increased, scale: scale, font: font(button), icon: icon)
                barHits.append((box, button.action))
                if hoveredChip == button.action {
                    tip = (button, box)
                }
            }
        }
        NSColor.white.withAlphaComponent(increased ? 0.6 : 0.16).setFill()
        let dividerHeight = min(22, height - 8)
        for x in layout.dividers {
            NSBezierPath(rect: CGRect(x: frame.minX + x, y: (frame.midY - dividerHeight / 2).rounded(), width: 1, height: dividerHeight)).fill()
        }
        if let tip {
            drawTip(tip.button, over: tip.box, bar: frame, textSize: textSize, increased: increased)
        }
        updateBarElements(groups.flatMap { $0 }, frames: barHits.map(\.rect))
    }

    private func drawButton(_ button: BarButton, in box: CGRect, hovered: Bool, increased: Bool, scale: CGFloat, font: NSFont, icon: (BarButton, NSColor) -> NSImage?) {
        let radius = min(Theme.Radius.group, box.height / 2)
        let content: NSColor
        switch button.look {
        case .picked:
            // The ink control: the accent with a 1.5 pt black outline and a 2 pt black drop, on whole device pixels.
            let line = Theme.inkWidth(1.5, scale: scale)
            let drop = Theme.inkOffset(2, scale: scale)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: box.offsetBy(dx: 0, dy: -drop), xRadius: radius, yRadius: radius).fill()
            FloatingPanel.accentNS.setFill()
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: line / 2, dy: line / 2), xRadius: radius - line / 2, yRadius: radius - line / 2)
            outline.lineWidth = line
            NSColor.black.setStroke()
            outline.stroke()
            content = Self.ink
        case .plain, .toggle:
            if button.on || hovered {
                NSColor.white.withAlphaComponent(button.on ? 0.16 : 0.08).setFill()
                NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
            }
            let off: CGFloat = button.look == .toggle ? (increased ? 0.75 : 0.55) : (increased ? 1 : 0.82)
            content = NSColor.white.withAlphaComponent(button.on ? 1 : off)
        }
        var x = box.minX + 10
        if let image = icon(button, content) {
            let size = image.size
            if button.label == nil {
                x = (box.midX - size.width / 2).rounded()
            }
            image.draw(in: CGRect(x: x, y: (box.midY - size.height / 2).rounded(), width: size.width, height: size.height))
            x += size.width.rounded(.up) + (button.look == .picked ? 7 : 6)
        }
        if let label = button.label {
            let text = NSAttributedString(string: label, attributes: [
                .font: font, .foregroundColor: button.look == .picked ? content : NSColor.white,
            ])
            text.draw(at: CGPoint(x: x, y: (box.midY - text.size().height / 2).rounded()))
        }
    }

    /// The Ratio button's icon: a rounded rectangle of the ratio's shape, wide or tall as it's turned, in a square of `side`.
    private static func ratioIcon(_ widthOverHeight: CGFloat, side: CGFloat, color: NSColor) -> NSImage {
        let line: CGFloat = 1.5
        let room = side - line
        let size = widthOverHeight >= 1
            ? CGSize(width: room, height: room / widthOverHeight)
            : CGSize(width: room * widthOverHeight, height: room)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let rect = CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
            path.lineWidth = line
            color.setStroke()
            path.stroke()
            return true
        }
    }

    /// A floating panel's fill and 0.5 pt edge, dark in both appearances and solid with Increase Contrast or Reduce
    /// Transparency. The bar's shadow is drawn only outside it, so it doesn't darken the see-through fill.
    private func drawPanel(_ frame: CGRect, radius: CGFloat, opacity: Double, shadow: Bool, increased: Bool, in ctx: CGContext) {
        let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        if shadow {
            ctx.saveGState()
            let outside = NSBezierPath(rect: bounds)
            outside.append(shape)
            outside.windingRule = .evenOdd
            outside.addClip()
            FloatingPanel.shadowNS.set()
            NSColor.black.setFill()
            shape.fill()
            ctx.restoreGState()
        }
        FloatingPanel.fillNS(opacity, solid: FloatingPanel.solidNS).setFill()
        shape.fill()
        let edgeWidth = 1 / (window?.backingScaleFactor ?? 2)
        let edge = NSBezierPath(roundedRect: frame.insetBy(dx: edgeWidth / 2, dy: edgeWidth / 2), xRadius: radius - edgeWidth / 2, yRadius: radius - edgeWidth / 2)
        FloatingPanel.edgeNS(increased: increased).setStroke()
        edge.lineWidth = edgeWidth
        edge.stroke()
    }

    /// The hovered button's tooltip, from Capture › Window pick and delay: its name and keycap on a small dark panel, on the
    /// side of the bar away from the screen's edge.
    private func drawTip(_ button: BarButton, over box: CGRect, bar: CGRect, textSize: TextSize, increased: Bool) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }
        let name = NSAttributedString(string: button.name, attributes: [
            .font: NSFont.systemFont(ofSize: textSize.points(12)), .foregroundColor: NSColor.white,
        ])
        let key = NSAttributedString(string: button.key, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: textSize.points(10.5), weight: .bold), .foregroundColor: NSColor.white,
        ])
        let nameSize = name.size()
        let keySize = key.size()
        let capWidth = keySize.width.rounded(.up) + 10
        let width = 9 + nameSize.width.rounded(.up) + 8 + capWidth + 9
        let height = max(nameSize.height, keySize.height).rounded(.up) + 8
        let x = min(max(box.midX - width / 2, 8), bounds.width - width - 8).rounded()
        let y = barPlacement == .top ? bar.minY - 8 - height : bar.maxY + 8
        let tip = CGRect(x: x, y: y, width: width, height: height)
        tipFrame = tip
        drawPanel(tip, radius: 8, opacity: Self.tipOpacity, shadow: false, increased: increased, in: ctx)
        name.draw(at: CGPoint(x: tip.minX + 9, y: (tip.midY - nameSize.height / 2).rounded()))
        let cap = CGRect(x: tip.maxX - 9 - capWidth, y: (tip.midY - keySize.height / 2).rounded(), width: capWidth, height: keySize.height.rounded(.up))
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: cap, xRadius: 4, yRadius: 4).fill()
        key.draw(at: CGPoint(x: cap.minX + 5, y: cap.minY))
    }

    /// The bar's tooltip is a touch more solid than the bar, as the board draws it.
    private static let tipOpacity = 0.92

    // MARK: VoiceOver

    /// The bar's buttons as VoiceOver sees them, rebuilt only when one changes. They stay while the bar is faded, since the
    /// keys still work and a press through VoiceOver shows the bar again.
    private var barElements: [NSAccessibilityElement] = []
    private var barElementState: [String] = []

    private func updateBarElements(_ buttons: [BarButton], frames: [CGRect]) {
        let state = zip(buttons, frames).map { "\($0.name)|\($0.on)|\($1)" }
        guard state != barElementState else {
            return
        }
        barElementState = state
        barElements = zip(buttons, frames).map { button, frame in
            let action = button.action
            let element = BarElement { [weak self] in
                self?.controller.revealBar()
                self?.perform(action)
            }
            if case .mode = action {
                element.setAccessibilityRole(.radioButton)
                element.setAccessibilityValue(button.on ? 1 : 0)
            } else if action == .ratio {
                element.setAccessibilityRole(.popUpButton)
            } else if button.look == .toggle || action == .scrolling {
                element.setAccessibilityRole(.checkBox)
                element.setAccessibilitySubrole(.toggle)
                element.setAccessibilityValue(button.on ? 1 : 0)
            } else {
                element.setAccessibilityRole(.button)
            }
            element.setAccessibilityLabel(button.name)
            element.setAccessibilityHelp(String(localized: "Key: \(button.key)"))
            element.setAccessibilityFrameInParentSpace(frame)
            element.setAccessibilityParent(self)
            return element
        }
    }

    override func accessibilityChildren() -> [Any]? {
        barElements
    }

    /// What the bar keeps off: an area made with the arrow keys, or the highlighted window or page. A full screen is picked with a click anywhere.
    private func aim(_ hole: CGRect?) -> OverlayBarPlacement.Aim? {
        guard let hole else {
            return nil
        }
        switch controller.target {
        case .area: return .area(hole)
        case .window: return .target(hole)
        case .screen: return nil
        }
    }
}

/// A button of the capture bar for VoiceOver, which the overlay draws rather than holding as a view.
private final class BarElement: NSAccessibilityElement {
    private let press: @MainActor @Sendable () -> Void

    init(press: @escaping @MainActor @Sendable () -> Void) {
        self.press = press
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        let press = press
        MainActor.assumeIsolated {
            press()
        }
        return true
    }
}
