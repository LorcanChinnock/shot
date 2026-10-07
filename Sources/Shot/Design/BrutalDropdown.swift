import AppKit
import ShotCore
import SwiftUI

struct BrutalMenuItem {
    let title: String
    var symbol: String?
    /// Shown only; the shortcut itself is handled elsewhere.
    var shortcut: String?
    var isSelected = false
    var isEnabled = true
    let action: () -> Void
}

enum BrutalMenuEntry {
    case button(BrutalMenuItem)
    case header(String)
    case divider

    static func item(_ title: String, symbol: String? = nil, shortcut: String? = nil, selected: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> Self {
        .button(BrutalMenuItem(title: title, symbol: symbol, shortcut: shortcut, isSelected: selected, isEnabled: enabled, action: action))
    }

    fileprivate var pickable: BrutalMenuItem? {
        if case .button(let item) = self, item.isEnabled {
            return item
        }
        return nil
    }
}

/// A button that opens a brutal-styled menu of `entries` under it. Style the button with `buttonStyle`, as for any button.
/// The menu is its own window, so it draws over everything in the window and is never clipped.
struct BrutalDropdown<Label: View>: View {
    /// What the menu is for, which VoiceOver reads as the button's label.
    let title: String
    let entries: [BrutalMenuEntry]
    @ViewBuilder let label: Label
    @State private var menu = DropdownMenu()

    var body: some View {
        Button {
            menu.open(title, entries)
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
    var entries: [BrutalMenuEntry] = []
    var highlighted: Int?
}

/// The open menu: a child window under the anchor that takes the keyboard and closes on a click anywhere else, like a
/// system menu, while its parent stays key.
@MainActor
private final class DropdownMenu {
    private static let gap = Brutal.minGap + 3
    private static let typeAheadPause: TimeInterval = 1

    weak var anchor: NSView?
    private let state = DropdownState()
    private var panel: NSPanel?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var typed = ""
    private var lastTyped = Date.distantPast

    func open(_ title: String, _ entries: [BrutalMenuEntry]) {
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
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .aqua)
        let list = DropdownList(title: title, state: state, minWidth: anchor?.bounds.width ?? 0, pick: { [weak self] in self?.pick($0) }, resize: { [weak self] in self?.place($0) })
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
    let title: String
    let state: DropdownState
    let minWidth: CGFloat
    let pick: (Int) -> Void
    let resize: (CGSize) -> Void

    var body: some View {
        let hasSymbols = state.entries.contains { entry in
            if case .button(let item) = entry {
                return item.symbol != nil
            }
            return false
        }
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
                    Text(header.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(Brutal.ink.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                case .divider:
                    Rectangle().fill(Brutal.ink.opacity(0.12))
                        .frame(height: 1.5)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                }
            }
        }
        .padding(Brutal.groupInset)
        .frame(minWidth: minWidth, alignment: .leading)
        .brutalSurface(Color.white, radius: 10, shadow: 3)
        // Room for the shadow, which draws outside the surface.
        .padding([.trailing, .bottom], 3)
        .fixedSize()
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { resize($0) }
    }
}

private struct DropdownRow: View {
    let item: BrutalMenuItem
    let hasSymbols: Bool
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if hasSymbols {
                    Image(systemName: item.symbol ?? "")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 16)
                }
                Text(item.title)
                    .font(Brutal.label)
                    .lineLimit(1)
                Spacer(minLength: 16)
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(Brutal.mono)
                        .foregroundStyle(Brutal.ink.opacity(0.5))
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .opacity(item.isSelected ? 1 : 0)
            }
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background {
                if highlighted && item.isEnabled {
                    Color.clear.brutalSurface(Brutal.yellow, radius: 7, shadow: 0, border: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.35)
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }
}
