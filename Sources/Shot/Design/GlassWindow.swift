import AppKit
import SwiftUI

/// Borderless-looking window whose SwiftUI content draws its own glass backdrop and ink border.
@MainActor
enum GlassWindow {
    static let cornerRadius: CGFloat = 18
    /// Leading space that keeps content clear of the traffic lights.
    static let trafficLightsWidth: CGFloat = 86
    /// A unified toolbar makes the title bar this tall and centers the traffic lights in it.
    static let titlebarHeight: CGFloat = 52

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
        return window
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
