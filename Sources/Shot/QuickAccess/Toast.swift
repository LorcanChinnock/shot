import AppKit

@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var label: NSTextField?
    private static var hideTask: Task<Void, Never>?

    /// Shows `message`; `duration` nil keeps it visible until the next call.
    static func show(_ message: String, duration: Duration? = .seconds(1.5)) {
        let panel = panel ?? makePanel()
        label?.stringValue = message
        label?.sizeToFit()
        let size = NSSize(width: (label?.frame.width ?? 100) + 40, height: 44)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 80)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        label?.frame.origin = NSPoint(x: 20, y: (size.height - (label?.frame.height ?? 0)) / 2)
        panel.orderFrontRegardless()
        hideTask?.cancel()
        guard let duration else {
            return
        }
        hideTask = Task {
            try? await Task.sleep(for: duration)
            if !Task.isCancelled {
                panel.orderOut(nil)
            }
        }
    }

    static func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.autoresizingMask = [.width, .height]
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        background.addSubview(label)
        panel.contentView = background
        self.panel = panel
        self.label = label
        return panel
    }
}
