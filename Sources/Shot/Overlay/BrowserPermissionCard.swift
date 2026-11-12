import AppKit
import ShotCore
import SwiftUI

/// The dark card the selection overlay shows when Browser is picked without Accessibility access (Capture › Permission
/// card…). It says why Shot needs the permission and offers Use Window, or Grant Access as the main button. It floats
/// just above the overlay in its own `FloatingPanelWindow`, so it adds no screen-sized layer, and takes the keyboard while
/// it shows: Return grants access and Esc closes the card, leaving the overlay in the mode it was in.
final class BrowserPermissionCard: FloatingPanelWindow {
    struct Actions {
        let useWindow: @MainActor () -> Void
        let grant: @MainActor () -> Void
        let close: @MainActor () -> Void
    }

    private let bar: CGRect?
    private let screenFrame: CGRect
    private let actions: Actions

    override var canBecomeKey: Bool { true }

    /// `bar` is the capture bar's frame in AppKit global space, or nil while it's hidden, and `screen` the frame of the
    /// display it's on.
    init(bar: CGRect?, screen: CGRect, actions: Actions) {
        self.bar = bar
        screenFrame = screen
        self.actions = actions
        let size = NSSize(width: BrowserPermissionCardView.width(Preferences().textSize), height: 180)
        super.init(contentRect: NSRect(origin: PermissionCardPlacement.origin(for: size, bar: bar, screen: screen), size: size))
        // Over the selection overlay, which sits at the screen saver level.
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSView(hosting: BrowserPermissionCardView(actions: actions) { [weak self] size in
            self?.fit(size)
        })
        contentView?.layoutSubtreeIfNeeded()
    }

    override func cancelOperation(_ sender: Any?) {
        actions.close()
    }

    /// Takes the height the text needs at the chosen text size, keeping the card next to the bar.
    private func fit(_ size: CGSize) {
        let wanted = NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard wanted != frame.size, wanted.width > 0, wanted.height > 0 else {
            return
        }
        setFrame(NSRect(origin: PermissionCardPlacement.origin(for: wanted, bar: bar, screen: screenFrame), size: wanted), display: true)
    }

    /// Reads the card out when it appears, since VoiceOver stays on the overlay under it.
    func announce() {
        let text = "\(BrowserPermissionCardView.title). \(BrowserPermissionCardView.detail)"
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}

private struct BrowserPermissionCardView: View {
    let actions: BrowserPermissionCard.Actions
    let onSize: (CGSize) -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.textSize) private var textSize

    static let padding: CGFloat = 18
    static let spacing: CGFloat = 10
    static let tile: CGFloat = 36
    /// The board gives Grant Access 1.3 times the width of Use Window.
    static let mainShare: CGFloat = 1.3
    static let buttonGap: CGFloat = 8

    static var title: String { String(localized: "Browser needs Accessibility") }
    static var detail: String {
        String(localized: "Shot uses it only to find where the page sits inside the browser window, so it can leave out the tabs and address bar.")
    }

    /// 300 pt on the board, wider with Settings › Text size so the text wraps as it does there.
    static func width(_ textSize: TextSize) -> CGFloat {
        (300 * CGFloat(textSize.scale)).rounded()
    }

    private var increased: Bool { contrast == .increased }

    var body: some View {
        let scale = CGFloat(textSize.scale)
        let width = Self.width(textSize)
        VStack(alignment: .leading, spacing: Self.spacing) {
            Image(systemName: "globe")
                .font(.scaled(18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: (Self.tile * scale).rounded(), height: (Self.tile * scale).rounded())
                .background(Color.white.opacity(increased ? 0.24 : 0.12), in: RoundedRectangle(cornerRadius: Brutal.Radius.group, style: .circular))
                .accessibilityHidden(true)
            Text(Self.title)
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(Self.detail)
                .font(.scaled(12.5))
                .lineSpacing(3)
                .foregroundStyle(increased ? Color.white : FloatingPanel.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ButtonRow(shares: [1, Self.mainShare], gap: Self.buttonGap) {
                Button { actions.useWindow() } label: {
                    Text("Use Window").frame(maxWidth: .infinity)
                }
                .buttonStyle(BrutalButtonStyle(floating: true))
                .help(String(localized: "Capture the whole window instead"))
                Button { actions.grant() } label: {
                    Text("Grant Access").frame(maxWidth: .infinity)
                }
                .buttonStyle(BrutalButtonStyle(.main, floating: true))
                .keyboardShortcut(.defaultAction)
                .help(String(localized: "Open the macOS prompt for Accessibility access"))
            }
            .padding(.top, 4)
        }
        .padding(Self.padding)
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .floatingPanel(RoundedRectangle(cornerRadius: Brutal.Radius.panel, style: .circular), opacity: FloatingPanel.Opacity.card)
        .onHover { inside in
            // The overlay's crosshair would otherwise stay over the buttons.
            (inside ? NSCursor.arrow : SelectionOverlayView.cursor).set()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.title)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }
}
