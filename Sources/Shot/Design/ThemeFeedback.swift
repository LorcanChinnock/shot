import ShotCore
import SwiftUI

// MARK: Fields

extension Theme {
    /// A quiet badge, such as Edited, and a keycap's face.
    static let badgeFill = Color(light: Color(hex: 0x16161A).opacity(0.08), dark: .white.opacity(0.1))
    /// A keycap's bottom edge.
    static let keycapEdge = Color(light: Color(hex: 0x16161A).opacity(0.12), dark: .white.opacity(0.14))
    /// A progress bar's track.
    static let progressTrack = Color(light: Color(hex: 0x16161A).opacity(0.08), dark: .white.opacity(0.12))
}

enum ThemeFieldKind {
    /// A box for typing a name or a number: the group fill with the Rest edge.
    case text
    /// A search field, or a field inside a row: the field fill with no edge.
    case search
}

extension View {
    /// Draws the box around a `.plain` text field, with the accent focus halo while `focused`. Pass the field's own
    /// `@FocusState`, since a modifier can't see the focus of the field inside it.
    func themeField(_ kind: ThemeFieldKind = .text, focused: Bool) -> some View {
        modifier(ThemeField(kind: kind, focused: focused))
    }
}

private struct ThemeField: ViewModifier {
    let kind: ThemeFieldKind
    let focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
        content
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(isEnabled ? Theme.ink : Theme.disabledText)
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(kind == .text ? Theme.group : Theme.fieldFill, in: shape)
            .modifier(FieldEdge(shape: shape, width: edgeWidth, color: edgeColor))
            .shadow(color: kind == .text && isEnabled ? restShadow : .clear, radius: 0.5, y: 1)
            .background {
                if focused, isEnabled {
                    Color.clear
                        .inkBorder(RoundedRectangle(cornerRadius: Theme.Radius.control + 4, style: .circular), width: 4, color: Theme.focusRing)
                        .padding(-4)
                }
            }
    }

    private var increased: Bool { contrast == .increased }

    /// The Rest edge for a text field. A search field has none, except with Increase Contrast, which edges both at 60% ink.
    private var edgeWidth: CGFloat {
        if increased { return 1 }
        guard kind == .text else { return 0 }
        return colorScheme == .dark ? 0.5 : 1
    }

    private var edgeColor: Color {
        if increased { return Theme.ink.opacity(0.6) }
        return isEnabled ? Theme.controlEdge : Theme.hairline
    }

    private var restShadow: Color { colorScheme == .dark ? .black.opacity(0.3) : Color(hex: 0x16161A).opacity(0.06) }
}

private struct FieldEdge<S: InsettableShape>: ViewModifier {
    let shape: S
    let width: CGFloat
    let color: Color

    func body(content: Content) -> some View {
        if width > 0 {
            content.inkBorder(shape, width: width, color: color)
        } else {
            content
        }
    }
}

/// A search field: a magnifying glass, the prompt in tertiary text, and a button that clears it once there's text.
struct ThemeSearchField: View {
    let prompt: LocalizedStringResource
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.scaled(12, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
                .accessibilityHidden(true)
            // The prompt is drawn behind the field rather than as its placeholder, which AppKit clips mid-letter when a
            // long translation doesn't fit; this one ends in "…".
            TextField(text: $text, prompt: Text(verbatim: "")) {
                Text(prompt)
            }
            .font(Theme.body)
            .frame(maxWidth: .infinity)
            .background(alignment: .leading) {
                if text.isEmpty {
                    Text(prompt)
                        .font(Theme.body)
                        .foregroundStyle(contrast == .increased ? Theme.ink : Theme.tertiaryText)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .focused(focus)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.scaled(12))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .themeField(.search, focused: focus.wrappedValue)
    }
}

// MARK: Tags and badges

/// A Finder tag: its name on a field-fill pill, after a dot in the tag's colour when it has one. While `isOn`, as a filter
/// that's on, it's tinted in selection blue.
struct TagChip: View {
    let name: String
    var color: Color?
    var isOn = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 5) {
            if let color {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(verbatim: name).lineLimit(1)
        }
        .font(.scaled(11.5, weight: isOn ? .semibold : .regular))
        .foregroundStyle(Theme.ink)
        .padding(.leading, color == nil ? 9 : 7)
        .padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(isOn ? Theme.selection.opacity(0.14) : Theme.fieldFill, in: Capsule())
        .modifier(FieldEdge(shape: Capsule(), width: isOn || contrast == .increased ? 1 : 0, color: isOn ? Theme.selection.opacity(contrast == .increased ? 1 : 0.35) : Theme.ink.opacity(0.6)))
        .contentShape(Capsule())
    }
}

/// A small label on a tile or beside a title, such as GIF, Edited or a version number.
struct ThemeBadge: View {
    enum Style {
        /// A faint fill with secondary text, beside titles and in rows.
        case quiet
        /// Near-black with white text, for badges over a thumbnail or a picture.
        case strong
    }

    let text: String
    var style: Style = .quiet
    /// A status dot before the text, such as success green for a permission that's allowed.
    var dot: Color?

    init(text: LocalizedStringResource, style: Style = .quiet, dot: Color? = nil) {
        self.init(text: String(localized: text), style: style, dot: dot)
    }

    /// A badge whose text is already localized, or is a number or name.
    @_disfavoredOverload
    init<S: StringProtocol>(text: S, style: Style = .quiet, dot: Color? = nil) {
        self.text = String(text)
        self.style = style
        self.dot = dot
    }

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text)
                .tracking(style == .strong ? 0.4 : 0)
                .lineLimit(1)
        }
        .font(.scaled(10.5, weight: style == .strong ? .bold : .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(style == .strong ? Color(hex: 0x16161A) : Theme.badgeFill, in: RoundedRectangle(cornerRadius: Theme.Radius.tiny, style: .circular))
    }

    private var foreground: Color {
        if style == .strong { return .white }
        return contrast == .increased ? Theme.ink : Theme.secondaryText
    }
}

/// A key, such as M or ⌘Z, in SF Mono on a field-fill cap with a 1 pt bottom edge.
struct Keycap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tiny, style: .circular)
        Text(verbatim: key)
            .font(Theme.keycap)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 18)
            .background(Theme.badgeFill, in: shape)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.keycapEdge).frame(height: 1)
            }
            .clipShape(shape)
            .fixedSize()
    }
}

// MARK: Progress

/// A 6 pt bar filled in ink to `value`, from 0 to 1. VoiceOver reads it as a progress indicator with its percentage.
struct ThemeProgressBar: View {
    let value: Double
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fraction = min(max(value, 0), 1)
        Capsule()
            .fill(contrast == .increased ? Theme.ink.opacity(0.25) : Theme.progressTrack)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.ink)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? proxy.size.height : 0))
                }
            }
            .frame(height: 6)
            .animation(reduceMotion ? nil : .linear(duration: 0.2), value: fraction)
            .accessibilityRepresentation {
                ProgressView(value: fraction)
            }
    }
}

// MARK: Empty states

/// What a list or grid shows with nothing in it: an accent tile in ink, a title, what to do next and any buttons.
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    var message: String?
    @ViewBuilder let actions: Actions

    init(symbol: String, title: LocalizedStringResource, message: LocalizedStringResource? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.init(symbol: symbol, title: String(localized: title), message: message.map { String(localized: $0) }, actions: actions)
    }

    /// An empty state whose text is already localized, such as a message with a path in it.
    @_disfavoredOverload
    init<S: StringProtocol>(symbol: String, title: S, message: String? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.symbol = symbol
        self.title = String(title)
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 8) {
            EmptyStateTile(symbol: symbol)
            Text(title)
                .font(.scaled(14, weight: .bold))
                .foregroundStyle(Theme.ink)
            if let message {
                Text(message)
                    .font(.scaled(12))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
        .padding(16)
        .accessibilityElement(children: .contain)
    }
}

/// The 44 pt accent tile with a 1.5 pt ink outline and a 2 pt drop.
private struct EmptyStateTile: View {
    let symbol: String
    @Environment(\.displayScale) private var scale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular)
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color(hex: 0x16161A))
            .frame(width: 44, height: 44)
            .background(Theme.accent, in: shape)
            .inkBorder(shape, width: 1.5)
            .background {
                shape.fill(Theme.line).offset(y: Theme.inkOffset(2, scale: scale))
            }
            .padding(.bottom, 2)
            .accessibilityHidden(true)
    }
}
