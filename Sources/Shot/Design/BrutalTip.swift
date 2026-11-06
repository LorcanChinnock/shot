import AppKit
import Combine
import ShotCore
import SwiftUI

private struct HostsTipsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a `tipHost()`; elsewhere `brutalTip` falls back to the system tooltip.
    var hostsTips: Bool {
        get { self[HostsTipsKey.self] }
        set { self[HostsTipsKey.self] = newValue }
    }
}

extension View {
    /// Explains the view in a tip after a hover, or when it takes keyboard focus: `title`, then `key` on a keycap when the
    /// view has a shortcut, with `detail` below them when there is one.
    /// VoiceOver reads the tip as a hint, not a label, since most titles add a shortcut to a button's own text, so a
    /// control without readable text, such as an icon, needs its own `accessibilityLabel`.
    func brutalTip(_ title: LocalizedStringResource, key: String? = nil, detail: LocalizedStringResource? = nil) -> some View {
        modifier(TipTrigger(title: String(localized: title), key: key, detail: detail.map { String(localized: $0) }))
    }

    /// A tip whose text is already localized, or needs no translating, as `Text` takes a string variable as is.
    @_disfavoredOverload
    func brutalTip<S: StringProtocol>(_ title: S, key: String? = nil, detail: String? = nil) -> some View {
        modifier(TipTrigger(title: String(title), key: key, detail: detail))
    }

    /// Draws the tips of the views inside over all of them, kept within its bounds. Glass windows install it on their content.
    func tipHost() -> some View {
        environment(\.hostsTips, true)
            .overlayPreferenceValue(TipKey.self) { tips in
                GeometryReader { proxy in
                    ForEach(tips.indices, id: \.self) { index in
                        TipBubble(tip: tips[index], proxy: proxy)
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

private struct Tip {
    let title: String
    let key: String?
    let detail: String?
    let anchor: Anchor<CGRect>
}

private struct TipKey: SwiftUI.PreferenceKey {
    static let defaultValue: [Tip] = []

    static func reduce(value: inout [Tip], nextValue: () -> [Tip]) {
        value += nextValue()
    }
}

private struct TipTrigger: ViewModifier {
    let title: String
    let key: String?
    let detail: String?
    @Environment(\.hostsTips) private var hostsTips
    @State private var hovering = false
    /// Set by a click or a key press while the tip is wanted, so it gets out of the way of the work, such as typing in a
    /// search field. Moving the pointer away or focus to another control clears it.
    @State private var dismissed = false
    @State private var shows = false
    /// Keyboard focus shows the tip too, so someone who doesn't use a pointer still learns the name and the key.
    @FocusState private var focused: Bool
    /// A field keeps focus while its window is in the background, but its tip shouldn't show there.
    @Environment(\.appearsActive) private var appearsActive

    private var wanted: Bool { (hovering || (focused && appearsActive)) && !dismissed }

    func body(content: Content) -> some View {
        if hostsTips {
            content
                .accessibilityHint(Text(detail ?? title))
                .focused($focused)
                .onHover(perform: hover)
                .onDisappear { hover(false) }
                .onReceive(TipClock.shared.dismissals) {
                    if hovering || focused {
                        dismissed = true
                    }
                }
                // A Tab press dismisses the tip it leaves, then focus lands here and this tip shows.
                .onChange(of: focused) { _, isFocused in
                    if isFocused || !hovering {
                        dismissed = false
                    }
                }
                .task(id: wanted) {
                    guard wanted else {
                        shows = false
                        return
                    }
                    try? await Task.sleep(for: TipClock.shared.timing.delay)
                    guard !Task.isCancelled else {
                        return
                    }
                    shows = true
                    TipClock.shared.timing.shown()
                }
                .anchorPreference(key: TipKey.self, value: .bounds) { shows ? [Tip(title: title, key: key, detail: detail, anchor: $0)] : [] }
        } else {
            content.help([key.map { "\(title) (\($0))" } ?? title, detail].compactMap(\.self).joined(separator: "\n"))
        }
    }

    private func hover(_ inside: Bool) {
        guard inside != hovering else {
            return
        }
        hovering = inside
        if inside {
            TipClock.shared.timing.entered(at: .now)
        } else {
            if !focused {
                dismissed = false
            }
            TipClock.shared.timing.left(at: .now)
        }
    }
}

/// Shared by every tip, so moving between controls keeps tips warm, and a click or key press hides the tip showing.
@MainActor
private final class TipClock {
    static let shared = TipClock()

    var timing = TipTiming()
    let dismissals = PassthroughSubject<Void, Never>()

    private init() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [dismissals] event in
            dismissals.send()
            return event
        }
    }
}

/// Sits below the view, or above it near the bottom of the window, and grows away from the nearer side edge.
private struct TipBubble: View {
    private static let maxWidth: CGFloat = 280
    private static let gap: CGFloat = 6
    private static let margin: CGFloat = 8

    let tip: Tip
    let proxy: GeometryProxy

    var body: some View {
        let target = proxy[tip.anchor]
        let bounds = proxy.size
        let leading = target.midX < bounds.width / 2
        let below = target.maxY + 80 < bounds.height
        let minX = leading
            ? min(max(target.minX, Self.margin), bounds.width - Self.maxWidth - Self.margin)
            : max(min(target.maxX, bounds.width - Self.margin), Self.maxWidth + Self.margin) - Self.maxWidth
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(tip.title).font(Brutal.small).foregroundStyle(Brutal.ink)
                if let key = tip.key {
                    Keycap(key)
                }
            }
            if let detail = tip.detail {
                Text(detail).font(.scaled(12)).foregroundStyle(Brutal.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .depth(.float, fill: Brutal.group, radius: Brutal.Radius.control)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: Self.maxWidth, height: 0, alignment: Alignment(horizontal: leading ? .leading : .trailing, vertical: below ? .top : .bottom))
        .position(x: minX + Self.maxWidth / 2, y: below ? target.maxY + Self.gap : target.minY - Self.gap)
    }
}
