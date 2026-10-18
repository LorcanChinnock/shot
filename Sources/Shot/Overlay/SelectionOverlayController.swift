import AppKit
import os
import ShotCoreApple

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
    case fullDisplay(Int)
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class SelectionOverlayController {
    private(set) var windowMode: Bool
    /// CoreGraphics global space, front to back.
    let windows: [WindowInfo]
    let isLive: Bool
    /// What an agent asked the person to select, and who's asking, shown above the hint.
    let prompt: String?
    private(set) var hoveredWindow: WindowInfo?
    var aspectRatio = AspectRatio.free {
        didSet {
            for view in views {
                view.needsDisplay = true
            }
        }
    }
    /// A window picked with Tab holds the highlight until the mouse moves.
    private var isWindowPinned = false
    private var panels: [OverlayPanel] = []
    private var views: [SelectionOverlayView] = []
    private var continuation: CheckedContinuation<OverlaySelection?, Never>?
    private var magnifierTask: Task<Void, Never>?
    /// The modifier keys held by the event that ended the selection.
    private var endModifiers: NSEvent.ModifierFlags = []

    private init(windowMode: Bool, windows: [WindowInfo], isLive: Bool, prompt: String?) {
        self.windowMode = windowMode
        self.windows = windows
        self.isLive = isLive
        self.prompt = prompt
    }

    /// The area, window or display the person picks, or nil when they cancel. With `timeout`, the overlay closes by
    /// itself after that long, as a cancel does.
    static func select(displays: [OverlayDisplay], windowMode: Bool, windows: [WindowInfo], isLive: Bool = false, prompt: String? = nil, timeout: Duration? = nil) async -> OverlaySelection? {
        await selectWithModifiers(displays: displays, windowMode: windowMode, windows: windows, isLive: isLive, prompt: prompt, timeout: timeout).selection
    }

    /// Like `select`, also returning the modifier keys held as the selection ended, read from that event rather than later.
    static func selectWithModifiers(displays: [OverlayDisplay], windowMode: Bool, windows: [WindowInfo], isLive: Bool = false, prompt: String? = nil, timeout: Duration? = nil) async -> (selection: OverlaySelection?, modifiers: NSEvent.ModifierFlags) {
        let controller = SelectionOverlayController(windowMode: windowMode, windows: windows, isLive: isLive, prompt: prompt)
        let expiry = timeout.map { timeout in
            Task { [weak controller] in
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled {
                    controller?.finish(nil)
                }
            }
        }
        // The overlay views hold the controller unowned; keep it alive until the user finishes.
        let selection = await withCheckedContinuation { continuation in
            controller.continuation = continuation
            controller.show(displays)
            if isLive, Preferences().showMagnifier {
                controller.loadMagnifierImages()
            }
        }
        expiry?.cancel()
        controller.magnifierTask?.cancel()
        withExtendedLifetime(controller) {}
        return (selection, controller.endModifiers)
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

    func toggleWindowMode() {
        windowMode.toggle()
        isWindowPinned = false
        updateHover(redraw: true)
    }

    func updateHover(redraw: Bool = false) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = Geometry.flip(NSEvent.mouseLocation, primaryHeight: primaryHeight)
        guard !isWindowPinned else {
            return
        }
        let hovered = windowMode ? WindowInfo.topmost(at: point, in: windows) : nil
        guard redraw || hovered != hoveredWindow else {
            return
        }
        hoveredWindow = hovered
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
