import AppKit
import SwiftUI

/// Borderless-looking window whose SwiftUI content draws its own glass backdrop and ink border.
@MainActor
enum GlassWindow {
    static let cornerRadius: CGFloat = 26
    /// Leading space that keeps content clear of the traffic lights.
    static let trafficLightsWidth: CGFloat = 86
    /// A unified toolbar makes the title bar this tall and centers the traffic lights in it.
    static let titlebarHeight: CGFloat = 52

    /// Glass windows are Shot's real UI, so while one is open Shot shows in the Dock and ⌘-Tab.
    private static let windows = NSHashTable<NSWindow>.weakObjects()
    private static var closeObserver: NSObjectProtocol?

    @discardableResult
    static func make<Content: View>(_ window: NSWindow? = nil, size: NSSize, title: String, resizable: Bool = false, @ViewBuilder content: () -> Content) -> NSWindow {
        let window = window ?? NSWindow()
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable {
            style.insert(.resizable)
        }
        window.styleMask = style
        window.setContentSize(size)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "glass")
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.contentView = NSHostingView(rootView: GlassChrome(content: content()))
        window.center()
        track(window)
        return window
    }

    static func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation is cooperative, so it can be refused (e.g. at launch, or right after the
        // policy change); raise the window anyway and ask again once the policy has settled.
        window.orderFrontRegardless()
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }

    private static func track(_ window: NSWindow) {
        windows.add(window)
        guard closeObserver == nil else {
            return
        }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            let id = (notification.object as? NSWindow).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let closing = windows.allObjects.first(where: { ObjectIdentifier($0) == id }) else {
                    return
                }
                let stillOpen = windows.allObjects.contains { $0 !== closing && ($0.isVisible || $0.isMiniaturized) }
                if !stillOpen {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}

private struct GlassChrome<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlassBackdrop())
            .clipShape(RoundedRectangle(cornerRadius: GlassWindow.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: GlassWindow.cornerRadius, style: .continuous).strokeBorder(Brutal.ink, lineWidth: 3))
            .environment(\.colorScheme, .light)
            .ignoresSafeArea()
    }
}
