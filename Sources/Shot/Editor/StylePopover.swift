import ShotCore
import SwiftUI

/// The shadow, border and corner radius of the selected image, or of the screenshot when nothing is selected.
/// Pointing at a preset shows it on the canvas; clicking it applies it. The sliders show only once there's a shadow to tune.
struct StylePopover: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let target = model.styleTarget {
                let style = model.targetStyle
                Text(target == .capture ? "SCREENSHOT STYLE" : "IMAGE STYLE")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Brutal.ink.opacity(0.75))
                row("SHADOW") {
                    tile("None", style, { $0.shadow = nil }, selected: style.shadow == nil) { Swatch() }
                    ForEach(ShadowPreset.allCases, id: \.self) { preset in
                        let shadow = preset.shadow(scale: model.scale)
                        tile(preset.title, style, { $0.shadow = shadow }, selected: style.shadow == shadow) { Swatch(shadow: preset) }
                    }
                }
                if let shadow = style.shadow {
                    shadowSliders(shadow)
                }
                row("BORDER") {
                    tile("None", style, { $0.border = nil }, selected: style.border == nil) { Swatch() }
                    tile("Hairline", style, { $0.border = .hairline }, selected: style.border == .hairline) { Swatch(hairline: true) }
                }
                row("CORNERS") {
                    slider(value: model.targetCornerRadius, range: 0...48, name: "Corner radius", set: model.setTargetCornerRadius)
                }
            } else {
                Text("Select an image, or nothing to style the screenshot.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.ink.opacity(0.6))
            }
        }
        .padding(14)
        .padding(.top, 6)
        .onDisappear { model.stylePreview = nil }
    }

    /// A preset tile for `style` with `change` made to it: pointing at it previews that, clicking applies it.
    private func tile<Picture: View>(
        _ title: String, _ style: ObjectStyle, _ change: (inout ObjectStyle) -> Void, selected: Bool, @ViewBuilder swatch: () -> Picture
    ) -> some View {
        var candidate = style
        change(&candidate)
        return StyleTile(title: title, selected: selected, preview: { [model, candidate] inside in
            if inside {
                model.stylePreview = candidate
            } else if model.stylePreview == candidate {
                // Moving straight onto another tile can report entering it before leaving this one.
                model.stylePreview = nil
            }
        }, action: { [model, candidate] in
            model.setTargetStyle(candidate)
        }, swatch: swatch())
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Brutal.mono)
                .foregroundStyle(Brutal.ink)
                .frame(width: 72, alignment: .leading)
            HStack(spacing: 4) {
                content()
            }
        }
    }

    /// Elevation and opacity, the two things that tune a shadow into a custom one.
    private func shadowSliders(_ shadow: Shadow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row("") {
                label("Elevation")
                slider(value: shadow.elevation / model.scale, range: Shadow.elevations, name: "Elevation", set: model.setShadowElevation)
                if ShadowPreset.matching(shadow, scale: model.scale) == nil {
                    BrutalChip(text: "CUSTOM", color: Brutal.sky)
                }
            }
            row("") {
                label("Opacity")
                slider(value: shadow.opacity, range: Shadow.opacities, name: "Opacity", set: model.setShadowOpacity)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Brutal.caption)
            .foregroundStyle(Brutal.ink.opacity(0.6))
            .frame(width: 60, alignment: .leading)
    }

    private func slider(value: CGFloat, range: ClosedRange<CGFloat>, name: String, set: @escaping (CGFloat) -> Void) -> some View {
        BrutalSlider(
            value: Binding(get: { Double(value) }, set: { set(CGFloat($0)) }),
            range: Double(range.lowerBound)...Double(range.upperBound),
            track: LinearGradient(colors: [.white, Brutal.sky], startPoint: .leading, endPoint: .trailing),
            width: 160,
            onEditingChanged: model.setDraggingStyle
        )
        .frame(height: 30)
        .accessibilityLabel(Text(name))
    }
}

/// A preset: a small picture of its look over its name.
private struct StyleTile<Picture: View>: View {
    let title: String
    let selected: Bool
    /// Called with true as the pointer moves onto the tile and false as it leaves.
    let preview: (Bool) -> Void
    let action: () -> Void
    let swatch: Picture
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                swatch.frame(width: 24, height: 16)
                Text(title).font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Brutal.ink)
            .frame(width: 56, height: 48)
            .background {
                if selected {
                    PartyColor(Brutal.sky) { Color.clear.brutalSurface($0, radius: 7, shadow: 2) }
                } else if hovering {
                    RoundedRectangle(cornerRadius: 7, style: .circular).fill(Brutal.ink.opacity(0.08))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { inside in
            hovering = inside
            preview(inside)
        }
    }
}

/// A white card with a preset's shadow or border, as a tile's picture.
private struct Swatch: View {
    var shadow: ShadowPreset?
    var hairline = false

    var body: some View {
        let card = RoundedRectangle(cornerRadius: 4, style: .circular)
        card.fill(.white)
            .overlay {
                if hairline {
                    card.stroke(Brutal.ink.opacity(0.45), lineWidth: 1)
                }
            }
            .shadow(color: color, radius: radius, y: offset)
    }

    private var color: Color {
        switch shadow {
        case nil: .clear
        case .glow: Brutal.sky
        case .contact: .black.opacity(0.45)
        case .soft, .float: .black.opacity(0.3)
        }
    }

    private var radius: CGFloat {
        switch shadow {
        case nil: 0
        case .contact: 1
        case .soft: 2.5
        case .float, .glow: 4
        }
    }

    private var offset: CGFloat {
        switch shadow {
        case nil, .glow: 0
        case .contact: 1
        case .soft: 2
        case .float: 4
        }
    }
}
