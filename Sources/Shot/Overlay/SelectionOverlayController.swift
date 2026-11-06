import AppKit
import os
import ShotCore

private let log = Logger.shot("overlay")

struct OverlayDisplay {
    /// AppKit global frame in points.
    let frame: CGRect
    let scale: CGFloat
    /// The frozen image; `nil` in live mode.
    let image: CGImage?
}

enum OverlaySelection {
    /// `rect` is in the display's view space: points, bottom-left origin. `ratio` is the width over height it was held to, if any.
    case area(display: Int, rect: CGRect, ratio: CGFloat?)
    case window(WindowInfo)
    /// A browser window's page alone, as how far it sits in from the window's edges.
    case page(WindowInfo, PageInsets)
    case fullDisplay(Int)
}

/// What the overlay returns: the pick, the modifiers held as it ended, the delay chosen before the capture starts, whether
/// the pick is to be scrolled, and the target it ended on, which the next overlay opens on.
struct OverlayResult {
    let selection: OverlaySelection?
    let modifiers: NSEvent.ModifierFlags
    let delay: Int
    let scrolling: Bool
    let target: CaptureTarget
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class SelectionOverlayController {
    private(set) var target: CaptureTarget
    /// Windows are highlighted for picking, whole or, for a browser, as just their page.
    var windowMode: Bool { target == .window }
    /// Whether a browser window is picked as just its page. It starts as Settings has it and B switches it for this overlay only.
    private(set) var pageOnly = Preferences().browserPageOnly
    var browserMode: Bool { windowMode && pageOnly && Permissions.hasAccessibility }
    var screenMode: Bool { target == .screen }
    /// The mode the capture bar shows as picked.
    var barMode: CaptureBarMode { CaptureBarMode(target: target, browserPage: browserMode) }
    /// Whether the pick is for a recording rather than a screenshot, which the bar names.
    let recording: Bool
    /// Seconds to wait after the pick before capturing; 0 is off. `offersDelay` is false where waiting makes no sense.
    private(set) var delay = 0
    let offersDelay: Bool
    /// Whether the pick can be scrolled, which only a screenshot does. Off until the person turns it on.
    let offersScrolling: Bool
    private(set) var scrolling = false
    /// CoreGraphics global space, front to back.
    let windows: [WindowInfo]
    let isLive: Bool
    private(set) var hoveredWindow: WindowInfo?
    /// The page of `hoveredWindow` in CoreGraphics global space, in browser mode.
    private(set) var hoveredPage: CGRect?
    var aspectRatio = AspectRatio.free {
        didSet {
            for view in views {
                view.needsDisplay = true
            }
        }
    }
    private var pageCache: [UInt32: CGRect?] = [:]
    /// A window picked with Tab holds the highlight until the mouse moves.
    private var isWindowPinned = false
    private var panels: [OverlayPanel] = []
    private var views: [SelectionOverlayView] = []
    private var continuation: CheckedContinuation<OverlaySelection?, Never>?
    private var magnifierTask: Task<Void, Never>?
    /// The loupe, guide lines and size readout start as Settings has them and are toggled for this overlay only.
    private(set) var showMagnifier = Preferences().showMagnifier
    private(set) var showCrosshair = Preferences().showCrosshair
    private(set) var showSizeLabel = Preferences().showSizeLabel
    /// The bar shows when the overlay opens and after each hotkey, then fades out after a pause so the area under it can be picked.
    /// 1 is fully shown, 0 is gone.
    private(set) var barOpacity: CGFloat = 1
    private var barTimer: Task<Void, Never>?
    private static let barLinger: Duration = .seconds(4)
    /// The modifier keys held by the event that ended the selection.
    private var endModifiers: NSEvent.ModifierFlags = []

    private init(target: CaptureTarget, offersDelay: Bool, offersScrolling: Bool, recording: Bool, windows: [WindowInfo], isLive: Bool) {
        self.target = target
        self.recording = recording
        self.offersDelay = offersDelay
        self.offersScrolling = offersScrolling
        self.windows = windows
        self.isLive = isLive
    }

    /// The area, window or display the person picks, or nil when they cancel.
    static func select(displays: [OverlayDisplay], target: CaptureTarget, windows: [WindowInfo], isLive: Bool = false) async -> OverlaySelection? {
        await select(displays: displays, target: target, offersDelay: false, windows: windows, isLive: isLive).selection
    }

    /// Like the above, also returning the modifier keys held as the selection ended, read from that event rather than
    /// later, and the delay chosen when `offersDelay`.
    static func select(
        displays: [OverlayDisplay], target: CaptureTarget, offersDelay: Bool, offersScrolling: Bool = false, recording: Bool = false, windows: [WindowInfo], isLive: Bool = false
    ) async -> OverlayResult {
        let controller = SelectionOverlayController(
            target: target, offersDelay: offersDelay, offersScrolling: offersScrolling, recording: recording, windows: windows, isLive: isLive
        )
        // The overlay views hold the controller unowned; keep it alive until the user finishes.
        let selection = await withCheckedContinuation { continuation in
            controller.continuation = continuation
            controller.show(displays)
            if isLive, Preferences().showMagnifier {
                controller.loadMagnifierImages()
            }
        }
        controller.magnifierTask?.cancel()
        controller.barTimer?.cancel()
        withExtendedLifetime(controller) {}
        return OverlayResult(selection: selection, modifiers: controller.endModifiers, delay: controller.delay, scrolling: controller.scrolling, target: controller.target)
    }

    private func show(_ displays: [OverlayDisplay]) {
        for (index, display) in displays.enumerated() {
            let panel = OverlayPanel(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = display.image != nil
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            let bounds = NSRect(origin: .zero, size: display.frame.size)
            let view = SelectionOverlayView(frame: bounds, display: display, index: index, controller: self)
            view.autoresizingMask = [.width, .height]
            let content = NSView(frame: bounds)
            content.wantsLayer = true
            // The frozen image sits in its own layer, so redrawing the overlay doesn't redraw it.
            if let image = display.image {
                let frozen = NSImageView(frame: bounds)
                frozen.image = NSImage(cgImage: image, size: bounds.size)
                frozen.imageScaling = .scaleAxesIndependently
                frozen.autoresizingMask = [.width, .height]
                content.addSubview(frozen)
            }
            content.addSubview(view)
            panel.contentView = content
            panel.setFrame(display.frame, display: false)
            panels.append(panel)
            views.append(view)
        }
        for panel in panels {
            panel.orderFrontRegardless()
        }
        let pointer = NSEvent.mouseLocation
        let keyPanel = panels.first { NSMouseInRect(pointer, $0.frame, false) } ?? panels.first
        if let keyPanel {
            keyPanel.makeKey()
            keyPanel.makeFirstResponder(views.first { $0.window === keyPanel })
        }
        updateHover(redraw: true)
        NSCursor.crosshair.set()
        revealBar()
    }

    /// Shows the bar and starts the pause after which it goes again; it stays while the pointer is on it.
    func revealBar() {
        barOpacity = 1
        barTimer?.cancel()
        barTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.barLinger)
                guard let self, !Task.isCancelled else {
                    return
                }
                if views.contains(where: \.pointerIsOnBar) {
                    continue
                }
                await fadeOutBar()
                return
            }
        }
        redrawAll()
    }

    /// Fades the bar out; moving onto it or a hotkey calls `revealBar`, which cancels the fade and shows it again.
    private func fadeOutBar() async {
        let clock = ContinuousClock()
        let start = clock.now
        // As long as a panel takes to leave, or Reduce Motion's fade.
        let fade = Duration.seconds(Motion.reduced ? Moment.reducedFade : Moment.panelArrive.duration)
        while !Task.isCancelled {
            let progress = min((clock.now - start) / fade, 1)
            barOpacity = CGFloat(1 - progress)
            redrawAll()
            if progress >= 1 {
                return
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func redrawAll() {
        for view in views {
            view.needsDisplay = true
        }
    }

    func toggleMagnifier() {
        showMagnifier.toggle()
        if showMagnifier, isLive, magnifierTask == nil {
            loadMagnifierImages()
        }
        redrawAll()
    }

    func toggleCrosshair() {
        showCrosshair.toggle()
        redrawAll()
    }

    func toggleSizeLabel() {
        showSizeLabel.toggle()
        redrawAll()
    }

    /// A live overlay has nothing frozen to magnify, so the loupe reads from stills taken while it is open.
    private func loadMagnifierImages() {
        magnifierTask = Task {
            let frozen: [FrozenDisplay]
            do {
                frozen = try await DisplayCapturer.captureForMagnifier()
            } catch is CancellationError {
                return
            } catch {
                log.error("Magnifier capture failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            for view in views {
                view.magnifierImage = frozen.first { $0.frame == view.display.frame }?.image
            }
        }
    }

    /// Space: between area and window, as in macOS. It lands on Window, not Browser, as Window's keycap says.
    func toggleWindowMode() {
        setMode(windowMode ? .area : .window)
    }

    /// Tab: area, window, then full screen, with page-only off so it reaches Window. Browser is reached with B.
    func cycleTarget(backward: Bool) {
        setMode(CaptureBarMode(target: target.next(backward: backward), browserPage: false))
    }

    func setTarget(_ newTarget: CaptureTarget) {
        guard newTarget != target else {
            return
        }
        target = newTarget
        isWindowPinned = false
        for view in views {
            view.targetChanged()
        }
        updateHover(redraw: true)
    }

    /// B: switches to Browser, which picks a browser window's page alone, or from Browser back to Window.
    func togglePageOnly() {
        setMode(barMode == .browser ? .window : .browser)
    }

    /// A click on one of the bar's modes. Browser needs Accessibility to find the page: without it the overlay closes and
    /// asks macOS for it, so the prompt isn't left behind the overlay.
    func setMode(_ mode: CaptureBarMode) {
        if mode.picksPage, !Permissions.hasAccessibility {
            finish(nil)
            Permissions.requestAccessibility()
            return
        }
        if mode.target == .window, pageOnly != mode.picksPage {
            pageOnly = mode.picksPage
            isWindowPinned = false
            if target == .window {
                updateHover(redraw: true)
            }
        }
        setTarget(mode.target)
    }

    func toggleScrolling() {
        guard offersScrolling else {
            return
        }
        scrolling.toggle()
        for view in views {
            view.needsDisplay = true
        }
    }

    func cycleDelay() {
        guard offersDelay else {
            return
        }
        delay = CaptureDelay.next(after: delay)
        for view in views {
            view.needsDisplay = true
        }
    }

    func updateHover(redraw: Bool = false) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = Geometry.flip(NSEvent.mouseLocation, primaryHeight: primaryHeight)
        guard !isWindowPinned else {
            return
        }
        let hovered = windowMode ? WindowInfo.topmost(at: point, in: windows) : nil
        // A window that isn't a browser has no page, so it is picked whole.
        let page = browserMode ? hovered.flatMap { pageRect(of: $0) } : nil
        guard redraw || hovered != hoveredWindow || page != hoveredPage else {
            return
        }
        hoveredWindow = hovered
        hoveredPage = page
        for view in views {
            view.needsDisplay = true
        }
    }

    func releaseKeyboardWindow() {
        isWindowPinned = false
    }

    /// Steps the window highlight front to back (back to front when `backward`) among the windows on a display, for use without a mouse.
    func stepWindow(backward: Bool) {
        let visible = windows.filter { window in
            panels.contains { $0.frame.intersects(appKitFrame(of: window)) }
        }
        guard !visible.isEmpty else {
            return
        }
        let current = hoveredWindow.flatMap { hovered in visible.firstIndex { $0 == hovered } }
        let next: Int
        if let current {
            next = (current + (backward ? visible.count - 1 : 1)) % visible.count
        } else {
            next = backward ? visible.count - 1 : 0
        }
        hoveredWindow = visible[next]
        isWindowPinned = true
        for view in views {
            view.needsDisplay = true
        }
        let name = [visible[next].ownerName, visible[next].title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        views.first?.announceWindow(name)
    }

    /// The page of a browser window in CoreGraphics global space, or nil for any other window or while Accessibility
    /// isn't allowed.
    private func pageRect(of window: WindowInfo) -> CGRect? {
        guard Permissions.hasAccessibility else {
            return nil
        }
        if let cached = pageCache[window.windowID] {
            return cached
        }
        let page = BrowserPageFinder.page(of: window)
        pageCache[window.windowID] = .some(page)
        return page
    }

    /// The highlighted page in AppKit global points.
    var hoveredPageFrame: CGRect? {
        hoveredPage.map { Geometry.flip($0, primaryHeight: NSScreen.screens.first?.frame.height ?? 0) }
    }

    /// What a click on `window` picks: the window, or in browser mode just its page.
    func selection(for window: WindowInfo) -> OverlaySelection {
        guard browserMode, let page = hoveredPage else {
            return .window(window)
        }
        return .page(window, PageInsets(window: window.frame, page: page))
    }

    /// AppKit global frame of a window.
    func appKitFrame(of window: WindowInfo) -> CGRect {
        Geometry.flip(window.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    func finish(_ selection: OverlaySelection?, modifiers: NSEvent.ModifierFlags = []) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        endModifiers = modifiers
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
        continuation.resume(returning: selection)
    }
}
