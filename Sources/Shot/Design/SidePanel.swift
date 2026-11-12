import SwiftUI

extension Theme {
    /// The side panels beside a canvas, such as the editor's Style and Layers panels.
    static let sidePanel = Color(light: Color(hex: 0xF1EFEA), dark: Color(hex: 0x242427))
}

extension View {
    /// A side panel flush with the canvas, from Edit › Image editor: `width` wide and as tall as it's given, on the side
    /// panel colour, with a hairline down its leading edge that Increase Contrast takes to 60% ink.
    func sidePanel(width: CGFloat) -> some View {
        modifier(SidePanelSurface(width: width))
    }
}

private struct SidePanelSurface: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: width)
            .frame(maxHeight: .infinity)
            // Not into the title bar's safe area, which a plain colour background fills.
            .background(Theme.sidePanel, ignoresSafeAreaEdges: [])
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(ContrastAware(standard: Theme.hairline, increased: Theme.ink.opacity(0.6)))
                    .frame(width: 1)
                    .accessibilityHidden(true)
            }
    }
}

/// Reset in a side panel's header, such as Style's and Export's: 12 pt medium accent text, faded when there's nothing to reset.
struct PanelLinkStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.scaled(12, weight: .medium))
            .foregroundStyle(isEnabled ? (contrast == .increased ? Theme.ink : Theme.accentText) : Theme.disabledText)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
    }
}

extension Text {
    /// A section's heading in a side panel, such as Style's Shadow or Export's Format: 11.5 pt semibold tertiary text,
    /// which Increase Contrast takes to the text colour.
    @MainActor func panelHeading() -> some View {
        font(.scaled(11.5, weight: .semibold))
            .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
            .accessibilityAddTraits(.isHeader)
    }
}

/// A side panel's name and value over the shared slider, as wide as the panel: Style's Padding or the Inspector's Scale.
/// `accessory` follows the value, such as the Inspector's keyframe diamond.
struct PanelSliderRow<Accessory: View>: View {
    let name: LocalizedStringResource
    let value: Double
    let range: ClosedRange<Double>
    /// The value as the row writes it, such as "72 pt".
    let shown: String
    let width: CGFloat
    let set: (Double) -> Void
    /// Called with true as a drag or a held arrow key starts and false as it ends, so the run is one undo step.
    let editing: (Bool) -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Text(verbatim: shown)
                    .font(.scaled(12, tabular: true))
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
                accessory
            }
            ThemeSlider(value: Binding(get: { value }, set: { set($0) }), range: range, width: width, onEditingChanged: editing)
                .frame(height: 18)
                .accessibilityLabel(Text(name))
                .accessibilityValue(Text(verbatim: shown))
        }
    }
}

extension PanelSliderRow where Accessory == EmptyView {
    init(
        name: LocalizedStringResource, value: Double, range: ClosedRange<Double>, shown: String, width: CGFloat,
        set: @escaping (Double) -> Void, editing: @escaping (Bool) -> Void
    ) {
        self.init(name: name, value: value, range: range, shown: shown, width: width, set: set, editing: editing) { EmptyView() }
    }
}
