import ShotCore
import SwiftUI

/// What the Style popover edits: the photo editor's selection or screenshot, or the video editor's selected clip. Sizes are
/// in points, which `scale` turns into the target's pixels.
@MainActor
protocol StyleEditing: AnyObject, Observable {
    var targetStyleKind: StyleKind? { get }
    /// The popover's heading.
    var targetStyleTitle: String { get }
    var targetHasTransparency: Bool { get }
    var targetStyle: ObjectStyle { get }
    var targetCornerRadius: CGFloat { get }
    var scale: CGFloat { get }
    /// A style the pointer is over, shown in place of the target's until it moves off.
    var stylePreview: ObjectStyle? { get set }
    var lastBorderColor: RGBA { get }
    func newBorder(_ kind: Border.Kind) -> Border
    func setTargetStyle(_ style: ObjectStyle)
    func setShadowElevation(_ points: CGFloat)
    func setShadowOpacity(_ opacity: CGFloat)
    func setBorderWidth(_ points: CGFloat)
    func setBorderColor(_ color: RGBA)
    func pickBorderColor(_ color: RGBA)
    func setTargetCornerRadius(_ points: CGFloat)
    func setDraggingStyle(_ dragging: Bool)
}

extension StyleEditing {
    var targetStyleTitle: String { targetStyleKind?.title ?? "" }
}

extension EditorModel: StyleEditing {}

/// The shadow, border and corner radius of the selected image, mark or text, or of the screenshot when nothing is selected.
/// Pointing at a preset shows it on the canvas; clicking it applies it. The sliders show only once there's a shadow to tune,
/// and the width and colour only once there's a border that has them. It offers only what the target can have.
struct StylePopover<Model: StyleEditing>: View {
    @Bindable var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let kind = model.targetStyleKind {
                let style = model.targetStyle
                let borders = kind.borders(transparent: model.targetHasTransparency)
                Text(model.targetStyleTitle)
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
                if !borders.isEmpty {
                    row("BORDER") {
                        tile("None", style, { $0.border = nil }, selected: style.border == nil) { Swatch() }
                        ForEach(borders, id: \.self) { borderKind in
                            let border = model.newBorder(borderKind)
                            tile(borderKind.title, style, { $0.border = border }, selected: style.border?.kind == borderKind) { Swatch(border: borderKind) }
                        }
                    }
                    if let border = style.border, border.kind != .hairline {
                        borderOptions(border, on: kind)
                    }
                }
                if kind.takesCorners {
                    row("CORNERS") {
                        slider(value: model.targetCornerRadius, range: 0...48, name: "Corner radius", set: model.setTargetCornerRadius)
                    }
                }
            } else {
                Text("Select an image, shape, arrow or text, or nothing to style the screenshot.")
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

    /// The width, S, M or L, and the colour of a solid border or an outline.
    private func borderOptions(_ border: Border, on kind: StyleKind) -> some View {
        let widths = Border.widths(border.kind, on: kind)
        return VStack(alignment: .leading, spacing: 4) {
            row("") {
                label("Width")
                ForEach(widths.indices, id: \.self) { index in
                    let points = widths[index]
                    Tile(selected: abs(points * model.scale - border.width) < 0.01, color: Brutal.sky, help: Self.sizeNames[index]) {
                        model.setBorderWidth(points)
                    } label: {
                        Text(Self.sizeNames[index].prefix(1)).font(.system(size: 12, weight: .heavy))
                    }
                }
            }
            row("") {
                label("Colour")
                ColorSwatches(
                    selected: border.paint,
                    lastCustom: model.lastBorderColor,
                    customHelp: "Custom border colour",
                    choose: { if let color = $0 { model.setBorderColor(color) } },
                    pickCustom: model.pickBorderColor
                )
            }
        }
    }

    private static var sizeNames: [String] { ["Small", "Medium", "Large"] }

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

extension StyleKind {
    /// The Style popover's heading.
    var title: String {
        switch self {
        case .capture: "SCREENSHOT STYLE"
        case .image: "IMAGE STYLE"
        case .mark: "SHAPE STYLE"
        case .text: "TEXT STYLE"
        }
    }
}

extension Border.Kind {
    var title: String {
        switch self {
        case .hairline: "Hairline"
        case .solid: "Solid"
        case .outline: "Outline"
        }
    }
}

/// A white card with a preset's shadow or border, as a tile's picture; an outline's is a cut-out disc with a white rim.
private struct Swatch: View {
    var shadow: ShadowPreset?
    var border: Border.Kind?

    var body: some View {
        let card = RoundedRectangle(cornerRadius: 4, style: .circular)
        if border == .outline {
            Circle().fill(Brutal.sky)
                .padding(3)
                .background(Circle().fill(.white))
                .overlay(Circle().stroke(Brutal.ink.opacity(0.45), lineWidth: 1))
                .frame(width: 16, height: 16)
        } else {
            card.fill(.white)
                .overlay {
                    switch border {
                    case .hairline: card.stroke(Brutal.ink.opacity(0.45), lineWidth: 1)
                    case .solid: card.stroke(Brutal.sky, lineWidth: 3)
                    case .outline, nil: EmptyView()
                    }
                }
                .shadow(color: color, radius: radius, y: offset)
        }
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
