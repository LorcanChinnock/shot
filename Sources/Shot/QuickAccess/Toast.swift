import AppKit
import SwiftUI

@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?
    private static let font = NSFont.systemFont(ofSize: 13, weight: .bold)
    private static let shadow: CGFloat = 4

    /// Shows `message`; `duration` nil keeps it visible until the next call.
    static func show(_ message: String, duration: Duration? = .seconds(1.5)) {
        let panel = panel ?? makePanel()
        let textWidth = (message as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        let size = NSSize(width: textWidth + 32 + shadow, height: 38 + shadow)
        panel.contentView = NSHostingView(fixedFrame: ToastView(message: message))
        let screen = NSScreen.underPointer ?? NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 80)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
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

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Brutal.ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .brutalSurface(Color.white.opacity(0.75), glass: true, radius: 10, shadow: 4)
            .padding(.trailing, 4)
            .padding(.bottom, 4)
            .environment(\.colorScheme, .light)
    }
}
