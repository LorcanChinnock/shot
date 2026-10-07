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
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "glass")
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.contentView = NSView(hosting: GlassChrome(content: content()))
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

extension NSView {
    /// A window's content view hosting SwiftUI one level down. A hosting view that is itself the content view resizes the
    /// window and sets its size limits from inside AppKit's layout pass, which throws once content changes under a visible window.
    convenience init(hosting rootView: some View) {
        self.init()
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }
}

private struct GlassChrome<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tipHost()
            .background(alignment: .top) {
                // Only the title strip moves the window; a drag anywhere else belongs to the content.
                TitleStrip()
                    .frame(height: GlassWindow.titlebarHeight)
            }
            .background(GlassBackdrop())
            .clipShape(RoundedRectangle(cornerRadius: GlassWindow.cornerRadius, style: .circular))
            .overlay(RoundedRectangle(cornerRadius: GlassWindow.cornerRadius, style: .circular).strokeBorder(Brutal.ink, lineWidth: 3))
            .environment(\.colorScheme, .light)
            .ignoresSafeArea()
    }
}

/// Drags the window and honours the system "double-click a window's title bar" setting.
private struct TitleStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { StripView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class StripView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2, let window else {
                window?.performDrag(with: event)
                return
            }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        }
    }
}
