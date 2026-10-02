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
    /// `rect` is in the display's view space: points, bottom-left origin.
    case area(display: Int, rect: CGRect)
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
    private var panels: [OverlayPanel] = []
    private var views: [SelectionOverlayView] = []
    private var continuation: CheckedContinuation<OverlaySelection?, Never>?

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
        let controller = SelectionOverlayController(windowMode: windowMode, windows: windows, isLive: isLive)
        return await withCheckedContinuation { continuation in
            controller.continuation = continuation
            controller.show(displays)
        }
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
            let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: display.frame.size), display: display, index: index, controller: self)
            panel.contentView = view
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
        keyPanel?.makeKey()
        keyPanel.flatMap { $0.contentView }.map { keyPanel?.makeFirstResponder($0) }
        updateHover()
        NSCursor.crosshair.set()
    }

    func toggleWindowMode() {
        windowMode.toggle()
        updateHover()
    }

    func updateHover() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = Geometry.flip(NSEvent.mouseLocation, primaryHeight: primaryHeight)
        hoveredWindow = windowMode ? WindowInfo.topmost(at: point, in: windows) : nil
        for view in views {
            view.needsDisplay = true
        }
    }

    /// AppKit global frame of a window.
    func appKitFrame(of window: WindowInfo) -> CGRect {
        Geometry.flip(window.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    func finish(_ selection: OverlaySelection?) {
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
        continuation.resume(returning: selection)
    }
}
