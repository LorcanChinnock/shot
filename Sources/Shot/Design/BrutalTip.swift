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
    /// Explains the view in a tip after a short hover: `title`, with `detail` below it when there is one.
    func brutalTip(_ title: String, detail: String? = nil) -> some View {
        modifier(TipTrigger(title: title, detail: detail))
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
    let detail: String?
    let anchor: Anchor<CGRect>
}

private struct TipKey: PreferenceKey {
    static let defaultValue: [Tip] = []

    static func reduce(value: inout [Tip], nextValue: () -> [Tip]) {
        value += nextValue()
    }
}

private struct TipTrigger: ViewModifier {
    let title: String
    let detail: String?
    @Environment(\.hostsTips) private var hostsTips
    @State private var hovering = false
    @State private var shows = false

    func body(content: Content) -> some View {
        if hostsTips {
            content
                .accessibilityHint(Text(detail ?? title))
                .onHover { hovering = $0 }
                .task(id: hovering) {
                    guard hovering else {
                        shows = false
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                    shows = !Task.isCancelled
                }
                .anchorPreference(key: TipKey.self, value: .bounds) { shows ? [Tip(title: title, detail: detail, anchor: $0)] : [] }
        } else {
            content.help([title, detail].compactMap(\.self).joined(separator: "\n"))
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
        PartyColor(.white) { color in
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title).font(Brutal.label)
                if let detail = tip.detail {
                    Text(detail).font(Brutal.caption).opacity(0.75)
                }
            }
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .brutalSurface(color, radius: 8, shadow: 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: Self.maxWidth, height: 0, alignment: Alignment(horizontal: leading ? .leading : .trailing, vertical: below ? .top : .bottom))
        .position(x: minX + Self.maxWidth / 2, y: below ? target.maxY + Self.gap : target.minY - Self.gap)
    }
}
