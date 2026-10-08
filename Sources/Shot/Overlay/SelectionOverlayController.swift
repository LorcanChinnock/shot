import AppKit
import ShotCore

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
    private(set) var hoveredWindow: WindowInfo?
    var aspectRatio = AspectRatio.free {
        didSet {
            for view in views {
                view.needsDisplay = true
            }
        }
    }
    private var panels: [OverlayPanel] = []
    private var views: [SelectionOverlayView] = []
    private var continuation: CheckedContinuation<OverlaySelection?, Never>?
    private var magnifierTask: Task<Void, Never>?
    /// The modifier keys held by the event that ended the selection.
    private var endModifiers: NSEvent.ModifierFlags = []

    private init(windowMode: Bool, windows: [WindowInfo], isLive: Bool) {
        self.windowMode = windowMode
        self.windows = windows
        self.isLive = isLive
    }

    static func onScreenWindows() -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return WindowInfo.parse(list, excludingPID: ProcessInfo.processInfo.processIdentifier)
    }

    static func select(displays: [OverlayDisplay], windowMode: Bool, windows: [WindowInfo], isLive: Bool = false) async -> OverlaySelection? {
        await selectWithModifiers(displays: displays, windowMode: windowMode, windows: windows, isLive: isLive).selection
    }

    /// Like `select`, also returning the modifier keys held as the selection ended, read from that event rather than later.
    static func selectWithModifiers(displays: [OverlayDisplay], windowMode: Bool, windows: [WindowInfo], isLive: Bool = false) async -> (selection: OverlaySelection?, modifiers: NSEvent.ModifierFlags) {
        let controller = SelectionOverlayController(windowMode: windowMode, windows: windows, isLive: isLive)
        // The overlay views hold the controller unowned; keep it alive until the user finishes.
        let selection = await withCheckedContinuation { continuation in
            controller.continuation = continuation
            controller.show(displays)
            if isLive, Preferences().showMagnifier {
                controller.loadMagnifierImages()
            }
        }
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
        NSApp.activate()
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
            guard let frozen = try? await DisplayCapturer.captureForMagnifier() else {
                return
            }
            for view in views {
                view.magnifierImage = frozen.first { $0.frame == view.display.frame }?.image
            }
        }
    }

    func toggleWindowMode() {
        windowMode.toggle()
        updateHover(redraw: true)
    }

    func updateHover(redraw: Bool = false) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = Geometry.flip(NSEvent.mouseLocation, primaryHeight: primaryHeight)
        let hovered = windowMode ? WindowInfo.topmost(at: point, in: windows) : nil
        guard redraw || hovered != hoveredWindow else {
            return
        }
        hoveredWindow = hovered
        for view in views {
            view.needsDisplay = true
        }
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
