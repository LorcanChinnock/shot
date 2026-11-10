import ShotCore
import SwiftUI

/// One of the target's own style sections, from Edit › Image editor · style: its corners, its shadow tiles with their
/// sliders, or its border tiles with the width and colour. The image editor's Style panel and the video editor's
/// Inspector both show them. Pointing at a tile shows it on the target; clicking it applies it.
struct StyleSection<Model: StyleEditing>: View {
    @Bindable var model: Model
    /// `.corners`, `.shadow` or `.border`; any other draws nothing.
    let section: StylePanelLayout.Section
    /// How wide the sliders are: the panel's width less its sides.
    let sliderWidth: CGFloat

    var body: some View {
        switch section {
        case .corners: corners
        case .shadow: shadow
        case .border: border
        default: EmptyView()
        }
    }

    private var corners: some View {
        PanelSliderRow(
            name: "Corners", value: Double(model.targetCornerRadius), range: 0...48, shown: "\(Int(model.targetCornerRadius.rounded())) pt",
            width: sliderWidth, set: { model.setTargetCornerRadius(CGFloat($0)) }, editing: model.setDraggingStyle
        )
    }

    private var shadow: some View {
        let style = model.targetStyle
        let shadows = [StylePreset(id: "shadow-none", title: String(localized: "None"), style: with(style) { $0.shadow = nil }, selected: style.shadow == nil, swatch: StylePresetSwatch())]
            + ShadowPreset.allCases.map { preset in
                let shadow = preset.shadow(scale: model.scale)
                return StylePreset(id: "shadow-\(preset.rawValue)", title: preset.title, style: with(style) { $0.shadow = shadow }, selected: style.shadow == shadow, swatch: StylePresetSwatch(shadow: preset))
            }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Shadow").panelHeading()
                if let shadow = style.shadow, ShadowPreset.matching(shadow, scale: model.scale) == nil {
                    BrutalBadge(text: "CUSTOM")
                }
            }
            grid(shadows)
            if let shadow = style.shadow {
                PanelSliderRow(
                    name: "Elevation", value: Double(shadow.elevation / model.scale),
                    range: Double(Shadow.elevations.lowerBound)...Double(Shadow.elevations.upperBound),
                    shown: "\(Int((shadow.elevation / model.scale).rounded())) pt", width: sliderWidth,
                    set: { model.setShadowElevation(CGFloat($0)) }, editing: model.setDraggingStyle
                )
                PanelSliderRow(
                    name: "Opacity", value: Double(shadow.opacity),
                    range: Double(Shadow.opacities.lowerBound)...Double(Shadow.opacities.upperBound),
                    shown: "\(Int((shadow.opacity * 100).rounded()))%", width: sliderWidth,
                    set: { model.setShadowOpacity(CGFloat($0)) }, editing: model.setDraggingStyle
                )
            }
        }
    }

    private var border: some View {
        let style = model.targetStyle
        let kinds = model.targetStyleKind?.borders(transparent: model.targetHasTransparency) ?? []
        let borders = [StylePreset(id: "border-none", title: String(localized: "None"), style: with(style) { $0.border = nil }, selected: style.border == nil, swatch: StylePresetSwatch())]
            + kinds.map { kind in
                let border = model.newBorder(kind)
                return StylePreset(id: "border-\(kind.rawValue)", title: kind.title, style: with(style) { $0.border = border }, selected: style.border?.kind == kind, swatch: StylePresetSwatch(border: kind))
            }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Border").panelHeading()
            grid(borders)
            if let border = style.border, border.kind != .hairline, let kind = model.targetStyleKind {
                borderOptions(border, on: kind)
            }
        }
    }

    private func with(_ style: ObjectStyle, _ change: (inout ObjectStyle) -> Void) -> ObjectStyle {
        var style = style
        change(&style)
        return style
    }

    private func grid(_ presets: [StylePreset]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(presets) { preset in
                StylePresetTile(preset: preset, model: model)
            }
        }
    }

    /// The width, S, M or L, and the colour of a solid border or an outline.
    private func borderOptions(_ border: Border, on kind: StyleKind) -> some View {
        let widths = Border.widths(border.kind, on: kind)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Width")
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                    .frame(width: 60, alignment: .leading)
                ForEach(widths.indices, id: \.self) { index in
                    let points = widths[index]
                    Tile(selected: abs(points * model.scale - border.width) < 0.01, help: WidthOptions.sizeNames[index]) {
                        model.setBorderWidth(points)
                    } label: {
                        Text(WidthOptions.sizeNames[index].prefix(1)).font(.scaled(12, weight: .heavy))
                    }
                }
            }
            Text("Colour")
                .font(.scaled(12, weight: .semibold))
                .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
            HStack(spacing: 2) {
                ColorSwatches(
                    selected: border.paint,
                    lastCustom: model.lastBorderColor,
                    customHelp: "Custom border colour",
                    choose: { if let color = $0 { model.setBorderColor(color) } },
                    pickCustom: { model.pickBorderColor($0) },
                    beginPicking: model.beginColorPick
                )
            }
        }
    }
}

/// A shadow or border tile: the target's style with one change made to it.
private struct StylePreset: Identifiable {
    let id: String
    let title: String
    let style: ObjectStyle
    let selected: Bool
    let swatch: StylePresetSwatch
}

/// A card with the preset's look over its name. The chosen one is the group fill with a 1.5 pt ring in the text colour,
/// as on the board. Pointing at it shows it on the target until the pointer moves off.
private struct StylePresetTile<Model: StyleEditing>: View {
    let preset: StylePreset
    let model: Model
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brutal.Radius.group, style: .circular)
        Button {
            model.setTargetStyle(preset.style)
        } label: {
            VStack(spacing: 5) {
                preset.swatch.frame(width: 26, height: 18)
                Text(verbatim: preset.title)
                    .font(.scaled(10.5, weight: preset.selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Brutal.ink)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .background {
                if preset.selected {
                    shape.fill(Brutal.group)
                } else if hovering {
                    shape.fill(Brutal.hover)
                }
            }
            .overlay {
                if preset.selected {
                    Color.clear.inkBorder(shape, width: 1.5, color: Brutal.ink)
                } else if contrast == .increased {
                    Color.clear.inkBorder(shape, width: 1, color: Brutal.ink.opacity(0.6))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: preset.title))
        .accessibilityAddTraits(preset.selected ? .isSelected : [])
        .onHover { inside in
            hovering = inside
            if inside {
                model.stylePreview = preset.style
            } else if model.stylePreview == preset.style {
                // Moving straight onto another tile can report entering it before leaving this one.
                model.stylePreview = nil
            }
        }
    }
}
