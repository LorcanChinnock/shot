import AppKit
import ShotCore
import SwiftUI

struct ThemeMenuItem {
    let title: String
    var symbol: String?
    /// Shown only; the shortcut itself is handled elsewhere.
    var shortcut: String?
    var isSelected = false
    var isEnabled = true
    let action: () -> Void
}

enum ThemeMenuEntry {
    case button(ThemeMenuItem)
    case header(String)
    case divider

    static func item(_ title: LocalizedStringResource, symbol: String? = nil, shortcut: String? = nil, selected: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> Self {
        item(String(localized: title), symbol: symbol, shortcut: shortcut, selected: selected, enabled: enabled, action: action)
    }

    /// An item whose title is already localized, or is a name such as a device's.
    @_disfavoredOverload
    static func item<S: StringProtocol>(_ title: S, symbol: String? = nil, shortcut: String? = nil, selected: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> Self {
        .button(ThemeMenuItem(title: String(title), symbol: symbol, shortcut: shortcut, isSelected: selected, isEnabled: enabled, action: action))
    }

    fileprivate var pickable: ThemeMenuItem? {
        if case .button(let item) = self, item.isEnabled {
            return item
        }
        return nil
    }
}

/// A button that opens a menu in the app's style of `entries` under it. Style the button with `buttonStyle`, as for any button.
/// The menu is its own window, so it draws over everything in the window and is never clipped.
struct ThemeDropdown<Label: View>: View {
    /// What the menu is for, which VoiceOver reads as the button's label.
    let title: LocalizedStringResource
    let entries: [ThemeMenuEntry]
    @ViewBuilder let label: Label
    @State private var menu = DropdownMenu()

    var body: some View {
        Button {
            menu.open(String(localized: title), entries)
        } label: {
            label
        }
        .background(DropdownAnchor(menu: menu))
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(selectedTitle ?? ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Opens a menu"))
        .onDisappear { menu.close() }
    }

    private var selectedTitle: String? {
        entries.lazy.compactMap { entry in
            if case .button(let item) = entry, item.isSelected {
                return item.title
            }
            return nil
        }.first
    }
}

/// A pop-up menu, from Components › Choice: the secondary button's look with the chosen value and up and down chevrons,
/// opening a menu of `entries` with the chosen one ticked. For a menu of commands rather than a choice, use `ThemeDropdown`.
struct ThemePopUp: View {
    let title: LocalizedStringResource
    let entries: [ThemeMenuEntry]
    /// The chosen value's title, already localized.
    let value: String
    var maxWidth: CGFloat?

    var body: some View {
        ThemeDropdown(title: title, entries: entries) {
            HStack(spacing: 10) {
                Text(value).lineLimit(1)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.scaled(9, weight: .bold))
                    .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
            }
        }
        .buttonStyle(ThemeButtonStyle(.popUp))
        // With a maximum width, the value shortens with an ellipsis when its row runs out of room, such as at a larger
        // text size, rather than pushing the row's title onto two lines.
        .fixedSize(horizontal: maxWidth == nil, vertical: true)
    }
}

private struct DropdownAnchor: NSViewRepresentable {
    let menu: DropdownMenu

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        menu.anchor = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        menu.anchor = nsView
    }

    private final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

@MainActor @Observable
private final class DropdownState {
    var entries: [ThemeMenuEntry] = []
    var highlighted: Int?
}

/// The open menu: a child window under the anchor that takes the keyboard and closes on a click anywhere else, like a
/// system menu, while its parent stays key.
@MainActor
private final class DropdownMenu {
    private static let gap = Theme.minGap + 3
    private static let typeAheadPause: TimeInterval = 1

    weak var anchor: NSView?
    private let state = DropdownState()
    private var panel: NSPanel?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var typed = ""
    private var lastTyped = Date.distantPast

    func open(_ title: String, _ entries: [ThemeMenuEntry]) {
        guard panel == nil, let window = anchor?.window else {
            return
        }
        state.entries = entries
        state.highlighted = entries.firstIndex { entry in
            if case .button(let item) = entry {
                return item.isSelected && item.isEnabled
            }
            return false
        }
        typed = ""

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 800), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The system draws the menu's shadow, as for a native menu, so it needs no room around the list.
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        let screenHeight = window.screen?.visibleFrame.height ?? 800
        let list = DropdownList(title: title, state: state, minWidth: anchor?.bounds.width ?? 0, maxHeight: screenHeight - Self.gap * 2, pick: { [weak self] in self?.pick($0) }, resize: { [weak self] in self?.place($0) })
        panel.contentView = NSView(hosting: list)
        self.panel = panel
        // Lays the list out now, so it reports its size and is placed before it shows.
        panel.contentView?.layoutSubtreeIfNeeded()
        window.addChildWindow(panel, ordered: .above)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            self?.handle(event) ?? event
        }
        let center = NotificationCenter.default
        for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject), (NSWindow.willCloseNotification, window), (NSApplication.didResignActiveNotification, NSApp)] {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.close()
                }
            })
        }
    }

    func close() {
        guard let panel else {
            return
        }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func place(_ size: CGSize) {
        guard let panel, let anchor, let window = anchor.window else {
            return
        }
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? rect.insetBy(dx: -size.width, dy: -size.height)
        let origin = Dropdown.origin(size: size, anchor: rect, visible: visible, gap: Self.gap)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()
    }

    private func pick(_ index: Int) {
        guard let item = state.entries[index].pickable else {
            return
        }
        close()
        // After the menu has gone and the event that picked it has finished, as a modal panel may open.
        Task { item.action() }
    }

    /// Returns the event to pass it on, or nil to swallow it.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown else {
            if event.window === panel {
                return event
            }
            close()
            // A click outside only closes the menu, as for a system menu; scrolling carries on.
            return event.type == .scrollWheel ? event : nil
        }
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            close()
            return event
        }
        let pickable = state.entries.map { $0.pickable != nil }
        switch event.keyCode {
        case 125:
            state.highlighted = Dropdown.step(from: state.highlighted, by: 1, pickable: pickable)
        case 126:
            state.highlighted = Dropdown.step(from: state.highlighted, by: -1, pickable: pickable)
        case 36, 76, 49:
            if let highlighted = state.highlighted {
                pick(highlighted)
            } else {
                close()
            }
        case 53:
            close()
        default:
            typeAhead(event.charactersIgnoringModifiers ?? "")
        }
        return nil
    }

    private func typeAhead(_ characters: String) {
        guard characters.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) else {
            return
        }
        let now = Date()
        typed = now.timeIntervalSince(lastTyped) < Self.typeAheadPause ? typed + characters : characters
        lastTyped = now
        let titles = state.entries.map { $0.pickable?.title }
        if let match = Dropdown.match(typed, titles: titles, from: state.highlighted) {
            state.highlighted = match
        }
    }
}

private struct DropdownList: View {
    /// The list's inset from the menu's edge.
    private static let inset: CGFloat = 5

    let title: String
    let state: DropdownState
    let minWidth: CGFloat
    /// The tallest the panel may be, shadow room included; a longer list scrolls.
    let maxHeight: CGFloat
    let pick: (Int) -> Void
    let resize: (CGSize) -> Void
    @State private var contentSize = CGSize.zero

    /// What's left for the rows once the surface's padding and the shadow's room are taken off.
    private var rowsHeight: CGFloat {
        maxHeight - Self.inset * 2
    }

    var body: some View {
        let hasSymbols = state.entries.contains { entry in
            if case .button(let item) = entry {
                return item.symbol != nil
            }
            return false
        }
        let overflows = contentSize.height > rowsHeight
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.entries.indices, id: \.self) { index in
                        switch state.entries[index] {
                        case .button(let item):
                            DropdownRow(item: item, hasSymbols: hasSymbols, highlighted: state.highlighted == index) {
                                pick(index)
                            }
                            .onHover { inside in
                                if inside, item.isEnabled {
                                    state.highlighted = index
                                }
                            }
                        case .header(let header):
                            Text(header)
                                .font(.scaled(11, weight: .semibold))
                                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                                .padding(.horizontal, 10)
                                .padding(.top, 4)
                                .padding(.bottom, 2)
                        case .divider:
                            Rectangle().fill(ContrastAware(standard: Theme.separator, increased: Theme.ink.opacity(0.6)))
                                .frame(height: 1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
                .padding(.trailing, overflows ? SystemScroller.shared.overlayRoom : 0)
            }
            .frame(width: contentSize.width > 0 ? contentSize.width + (overflows ? SystemScroller.shared.width : 0) : nil,
                   height: contentSize.height > 0 ? min(contentSize.height, rowsHeight) : nil)
            .onChange(of: state.highlighted) { _, index in
                if let index {
                    proxy.scrollTo(index)
                }
            }
            .onAppear {
                if let index = state.highlighted {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .padding(Self.inset)
        .frame(minWidth: minWidth, alignment: .leading)
        .modifier(MenuSurface())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { resize($0) }
    }
}

/// A native menu's surface: the group fill and the Float depth's 0.5 pt edge. The window draws the shadow.
private struct MenuSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular)
        let edge = contrast == .increased ? Theme.ink.opacity(0.6) : Color(light: .black.opacity(0.2), dark: .white.opacity(0.14))
        content
            .background(Theme.group, in: shape)
            .inkBorder(shape, width: contrast == .increased ? 1 : 0.5, color: edge)
    }
}

private struct DropdownRow: View {
    let item: ThemeMenuItem
    let hasSymbols: Bool
    let highlighted: Bool
    let action: () -> Void

    private var lit: Bool { highlighted && item.isEnabled }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if hasSymbols {
                    Image(systemName: item.symbol ?? "")
                        .font(.scaled(12, weight: .medium))
                        .frame(width: 16)
                }
                Text(item.title)
                    .font(Theme.body)
                    .lineLimit(1)
                Spacer(minLength: 16)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(Theme.mono)
                        .foregroundStyle(highlighted ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink)))
                }
                Image(systemName: "checkmark")
                    .font(.scaled(11, weight: .semibold))
                    .opacity(item.isSelected ? 1 : 0)
            }
            .foregroundStyle(item.isEnabled ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.disabledText))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .inkOnFill(lit ? Theme.accent : nil)
            .background {
                // The highlighted row, as the menu bar menu draws it: the accent with a faint ink inner edge.
                if lit {
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
                    shape.fill(Theme.accent)
                        .inkBorder(shape, width: 1, color: Color(hex: 0x16161A).opacity(0.4))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }
}
