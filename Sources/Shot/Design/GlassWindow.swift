import AppKit
import ShotCore
import SwiftUI

/// A standard Mac window with a unified title bar: the toolbar sits in it beside the traffic lights, and SwiftUI content
/// fills the window under it on the plain window background. The system draws the corners and the edge.
@MainActor
enum GlassWindow {
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
        window.backgroundColor = NSColor(Brutal.window)
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "glass")
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        setContent(of: window, content: content)
        window.center()
        track(window)
        return window
    }

    static func setContent<Content: View>(of window: NSWindow, @ViewBuilder content: () -> Content) {
        // Only the title strip moves the window, so a click on a button in the title bar presses it.
        window.contentView = NSView(hosting: GlassChrome(content: content()), movesWindow: false)
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
    /// `movesWindow` false keeps AppKit from dragging the window from anywhere in the content, so only a view that drags
    /// it itself, such as a glass window's title strip, does.
    convenience init(hosting rootView: some View, movesWindow: Bool = true) {
        self.init()
        let content = rootView.modifier(TextSizeRoot())
        let hosting = movesWindow ? NSHostingView(rootView: content) : StillHostingView(rootView: content) as NSHostingView
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }
}

/// A hosting view a mouse-down never drags the window from, even over a button inside a transparent title bar.
private final class StillHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Hands Settings › General › Text size to everything a hosting view shows.
private struct TextSizeRoot: ViewModifier {
    @Setting(PreferenceKey.textSize) private var textSize: TextSize

    func body(content: Content) -> some View {
        content.environment(\.textSize, textSize)
    }
}

private struct GlassChrome<Content: View>: View {
    let content: Content

    var body: some View {
        content
            // Zero minimums size the chrome to the window, not to content that is shorter or wider than it.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .tipHost()
            .background(alignment: .top) {
                // Only the title strip moves the window; a drag anywhere else belongs to the content.
                TitleStrip()
                    .frame(height: GlassWindow.titlebarHeight)
            }
            .background(GlassBackdrop())
            .ignoresSafeArea()
    }
}

/// Drags the window and honours the system "double-click a window's title bar" setting. It's SwiftUI, not an AppKit view:
/// AppKit hands a click to an `NSView` under a SwiftUI button before the button, so a view here took the title bar's
/// buttons' clicks and dragged the window instead.
private struct TitleStrip: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            // A second click without a move; the drag gesture never starts without one.
            .simultaneousGesture(TapGesture().onEnded {
                guard let event = NSApp.currentEvent, event.clickCount == 2, let window = event.window else {
                    return
                }
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            })
            // The first click on a window in the background drags it too.
            .allowsWindowActivationEvents(true)
    }
}

// MARK: Sidebar material

/// A sidebar's see-through material: the desktop shows through it, tinted by the sidebar colour. It turns solid, in the
/// sidebar colour, with Reduce Transparency or Increase Contrast on. Sidebar tints never fill it.
struct SidebarMaterial: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if contrast == .increased || reduceTransparency {
            Brutal.sidebar
        } else {
            SidebarEffect()
        }
    }
}

private struct SidebarEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: Floating panels

/// The capture bar, recording controls, countdown, toasts, Quick Access buttons and pin bar float over whatever is on
/// screen, so they're dark in both appearances (#1073): a near-black fill the screen shows faintly through, a hairline
/// white edge and the system window shadow. Content in them lays out in the dark appearance.
enum FloatingPanel {
    /// The fill, at one of the `Opacity` levels.
    static let fill = Color(hex: 0x1A1A1E)

    /// How much of the screen shows through. Increase Contrast and Reduce Transparency make every panel solid.
    enum Opacity {
        /// The capture bar, recording controls and the countdown.
        static let standard = 0.86
        static let toast = 0.90
        /// Cards with a paragraph to read, such as the browser permission card.
        static let card = 0.92
        static let pinBar = 0.82
        /// Quick Access's round corner buttons, over the capture itself.
        static let cornerButton = 0.78
    }

    /// The 0.5 pt edge; 40% with Increase Contrast.
    static let edge = Color.white.opacity(0.14)
    /// Icons that aren't on, such as a toolbar button's symbol.
    static let icon = Color.white.opacity(0.82)
    /// A toggle that's off.
    static let offToggle = Color.white.opacity(0.55)
    /// Descriptions and hints under a panel's main text.
    static let secondaryText = Color.white.opacity(0.75)
    /// A 1 × 22 pt line between groups of buttons.
    static let divider = Color.white.opacity(0.16)
    /// Dims a Quick Access card under its hover buttons, so the capture still shows.
    static let scrim = Color(hex: 0x121216).opacity(0.46)
    /// Covers a Quick Access card waiting behind the newest, so only its dark top edge shows above it.
    static let cardBehind = Color(hex: 0x2A2A2E)

    /// The same values for the capture bar, which AppKit draws over the screen. `solid` is Increase Contrast or Reduce
    /// Transparency.
    static func fillNS(_ opacity: Double, solid: Bool) -> NSColor {
        NSColor(srgbRed: 0x1A / 255, green: 0x1A / 255, blue: 0x1E / 255, alpha: solid ? 1 : opacity)
    }

    /// The accent and record red as they show on a floating panel: their dark values, as SwiftUI resolves them inside
    /// `floatingPanel`, since the panel is dark in both appearances.
    static let accentNS = NSColor(srgbRed: 0xF2 / 255, green: 0xCC / 255, blue: 0x4A / 255, alpha: 1)
    static let recordNS = NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)

    static func edgeNS(increased: Bool) -> NSColor { NSColor.white.withAlphaComponent(increased ? 0.4 : 0.14) }

    /// `0 14px 36px rgba(0,0,0,0.38)`, for a panel drawn into a view rather than in a window of its own.
    static var shadowNS: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        shadow.shadowBlurRadius = 18
        return shadow
    }

    /// Whether panels draw solid: Increase Contrast or Reduce Transparency is on.
    static var solidNS: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

/// `floatingPanel(_:opacity:)`'s modifier.
private struct FloatingPanelSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let opacity: Double
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let increased = contrast == .increased
        content
            .background(FloatingPanel.fill.opacity(increased || reduceTransparency ? 1 : opacity), in: shape)
            .inkBorder(shape, width: 0.5, color: .white.opacity(increased ? 0.4 : 0.14))
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Draws the view as a floating panel in `shape`. Put it in a `FloatingPanelWindow` sized to the shape, so the system
    /// shadow follows the shape and no transparent margin catches clicks.
    func floatingPanel<S: InsettableShape>(_ shape: S, opacity: Double = FloatingPanel.Opacity.standard) -> some View {
        modifier(FloatingPanelSurface(shape: shape, opacity: opacity))
    }
}

/// A borderless, non-activating panel for a floating panel. Its shadow is the system window shadow, which follows the
/// shape drawn in it and, unlike a shadow drawn in SwiftUI, needs no transparent margin that would catch clicks.
class FloatingPanelWindow: NSPanel {
    init(contentRect: NSRect, styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        refreshShadow()
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        refreshShadow()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        refreshShadow()
    }

    /// Works the shadow out again once the content has drawn in its new shape.
    func refreshShadow() {
        DispatchQueue.main.async { [weak self] in
            self?.invalidateShadow()
        }
    }
}

/// The 1 × 22 pt line between groups of buttons in a floating panel.
struct FloatingDivider: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(contrast == .increased ? 0.6 : 0.16))
            .frame(width: 1, height: 22)
            .accessibilityHidden(true)
    }
}
