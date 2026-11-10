import SwiftUI

extension Brutal {
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
            .background(Brutal.sidePanel, ignoresSafeAreaEdges: [])
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(ContrastAware(standard: Brutal.hairline, increased: Brutal.ink.opacity(0.6)))
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
            .foregroundStyle(isEnabled ? (contrast == .increased ? Brutal.ink : Brutal.accentText) : Brutal.disabledText)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
    }
}
