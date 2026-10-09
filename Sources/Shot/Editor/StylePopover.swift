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
    /// Whether the target is a window captured with the macOS shadow, which takes no shadow of its own.
    var targetHasWindowShadow: Bool { get }
    var targetStyle: ObjectStyle { get }
    var targetCornerRadius: CGFloat { get }
    /// What the preset tiles draw with each preset on it; `nil` draws a plain card instead.
    var targetThumbnail: StyleThumbnail.Subject? { get }
    /// The canvas background, which tints a tile's shadow as it does the target's.
    var thumbnailBackground: RGBA? { get }
    var scale: CGFloat { get }
    /// A style the pointer or the arrow keys are on, shown in place of the target's until they move off.
    var stylePreview: ObjectStyle? { get set }
    /// The colour last picked for a border in the custom colour editor; `nil` until one is.
    var lastBorderColor: RGBA? { get }
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
    var targetHasWindowShadow: Bool { false }
    var thumbnailBackground: RGBA? { nil }
}

/// The style Copy Style took last, in any editor window, photo or video, which Paste Style puts on the selection.
@MainActor
enum StyleClipboard {
    static var copied: CopiedStyle?
}

extension EditorModel: StyleEditing {}

/// The shadow, border and corner radius of the selected image, mark or text, or of the screenshot when nothing is selected.
/// Each preset tile shows the target with that preset on it. Pointing at a tile, or moving to it with the arrow keys,
/// shows it on the canvas; clicking it or pressing Return applies it. The sliders show only once there's a shadow to tune,
/// and the width and colour only once there's a border that has them. It offers only what the target can have.
struct StylePopover<Model: StyleEditing>: View {
    @Bindable var model: Model
    /// The tile the arrow keys are on, which Return applies.
    @State private var highlighted: String?
    @FocusState private var focused: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let kind = model.targetStyleKind {
                let style = model.targetStyle
                let rows = presetRows(kind, style)
                Text(model.targetStyleTitle)
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Brutal.ink.opacity(0.75))
                if model.targetHasWindowShadow {
                    row("SHADOW") {
                        Text("Uses macOS window shadow")
                            .font(Brutal.caption)
                            .foregroundStyle(Brutal.ink.opacity(0.6))
                            .brutalTip("This window was captured with its own shadow, so it takes no other")
                    }
                } else if let shadows = rows.first(where: { $0.title == "SHADOW" }) {
                    tiles(shadows)
                }
                if let shadow = style.shadow, !model.targetHasWindowShadow {
                    shadowSliders(shadow)
                }
                if let borders = rows.first(where: { $0.title == "BORDER" }) {
                    tiles(borders)
                    if let border = style.border, border.kind != .hairline {
                        borderOptions(border, on: kind)
                    }
                }
                if kind.takesCorners {
                    row("CORNERS") {
                        slider(value: model.targetCornerRadius, range: 0...48, name: "Corner radius", set: { model.setTargetCornerRadius($0) })
                    }
                }
                // Only the photo editor has a screenshot to style.
                if kind == .capture, let editor = model as? EditorModel {
                    NewCaptureStyleSwitch(model: editor)
                }
            } else {
                Text("Select an image, shape, arrow or text, or nothing to style the screenshot.")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.ink.opacity(0.6))
            }
        }
        .padding(14)
        .padding(.top, 6)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return]) { press in
            handle(press.key)
        }
        .onAppear { focused = true }
        .onDisappear { model.stylePreview = nil }
    }

    /// A row of preset tiles.
    private struct PresetRow {
        let title: String
        let presets: [Preset]
    }

    /// A preset tile: the target's style with one change made to it.
    private struct Preset: Identifiable {
        let id: String
        let title: String
        let style: ObjectStyle
        let selected: Bool
        /// The plain card drawn when there's no picture of the target.
        let swatch: Swatch
    }

    /// The shadow presets, which a window with the macOS shadow has none of, then the borders the target can have.
    private func presetRows(_ kind: StyleKind, _ style: ObjectStyle) -> [PresetRow] {
        func preset(_ id: String, _ title: String, selected: Bool, swatch: Swatch, _ change: (inout ObjectStyle) -> Void) -> Preset {
            var candidate = style
            change(&candidate)
            return Preset(id: id, title: title, style: candidate, selected: selected, swatch: swatch)
        }
        var rows: [PresetRow] = []
        if !model.targetHasWindowShadow {
            let shadows = [preset("shadow-none", "None", selected: style.shadow == nil, swatch: Swatch()) { $0.shadow = nil }]
                + ShadowPreset.allCases.map { shadowPreset in
                    let shadow = shadowPreset.shadow(scale: model.scale)
                    return preset("shadow-\(shadowPreset.rawValue)", shadowPreset.title, selected: style.shadow == shadow, swatch: Swatch(shadow: shadowPreset)) { $0.shadow = shadow }
                }
            rows.append(PresetRow(title: "SHADOW", presets: shadows))
        }
        let borderKinds = kind.borders(transparent: model.targetHasTransparency)
        if !borderKinds.isEmpty {
            let borders = [preset("border-none", "None", selected: style.border == nil, swatch: Swatch()) { $0.border = nil }]
                + borderKinds.map { borderKind in
                    let border = model.newBorder(borderKind)
                    return preset("border-\(borderKind.rawValue)", borderKind.title, selected: style.border?.kind == borderKind, swatch: Swatch(border: borderKind)) { $0.border = border }
                }
            rows.append(PresetRow(title: "BORDER", presets: borders))
        }
        return rows
    }

    private func tiles(_ presetRow: PresetRow) -> some View {
        row(presetRow.title) {
            ForEach(presetRow.presets) { preset in
                tile(preset)
            }
        }
    }

    /// A tile for `preset`: pointing at it previews it, clicking applies it.
    private func tile(_ preset: Preset) -> some View {
        StyleTile(
            title: preset.title,
            selected: preset.selected,
            highlighted: highlighted == preset.id,
            picture: picture(of: preset.style),
            preview: { [model] inside in
                if inside {
                    highlighted = preset.id
                    model.stylePreview = preset.style
                } else if model.stylePreview == preset.style {
                    // Moving straight onto another tile can report entering it before leaving this one.
                    model.stylePreview = nil
                }
            },
            action: { [model] in
                highlighted = preset.id
                model.setTargetStyle(preset.style)
            },
            swatch: preset.swatch
        )
    }

    private static var pictureSize: CGSize { CGSize(width: 48, height: 28) }

    /// The target drawn with `style`, or `nil` when there's no picture of it to draw.
    private func picture(of style: ObjectStyle) -> CGImage? {
        guard let subject = model.targetThumbnail else {
            return nil
        }
        return StyleThumbnail.render(
            subject, style: style.scaled(by: 1 / model.scale), cornerRadius: model.targetCornerRadius, size: Self.pictureSize,
            pixelsPerPoint: displayScale, background: model.thumbnailBackground
        )
    }

    /// The arrow keys move between tiles, previewing each, and Return applies the one they're on.
    private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        guard let kind = model.targetStyleKind else {
            return .ignored
        }
        let rows = presetRows(kind, model.targetStyle).map(\.presets)
        guard !rows.isEmpty else {
            return .ignored
        }
        let position = highlighted.flatMap { id in
            rows.indices.lazy.compactMap { row in rows[row].firstIndex { $0.id == id }.map { (row, $0) } }.first
        }
        if key == .return {
            guard let (row, column) = position else {
                return .ignored
            }
            model.setTargetStyle(rows[row][column].style)
            return .handled
        }
        var (row, column) = position ?? (0, rows[0].firstIndex(where: \.selected) ?? 0)
        // The first press lands on the tile the target has; later ones move from there.
        if position != nil {
            switch key {
            case .leftArrow: column -= 1
            case .rightArrow: column += 1
            case .upArrow: row -= 1
            default: row += 1
            }
            row = min(max(row, 0), rows.count - 1)
            column = min(max(column, 0), rows[row].count - 1)
        }
        let preset = rows[row][column]
        highlighted = preset.id
        model.stylePreview = preset.style
        return .handled
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
                slider(value: shadow.elevation / model.scale, range: Shadow.elevations, name: "Elevation", set: { model.setShadowElevation($0) })
                if ShadowPreset.matching(shadow, scale: model.scale) == nil {
                    BrutalChip(text: "CUSTOM", color: Brutal.sky)
                }
            }
            row("") {
                label("Opacity")
                slider(value: shadow.opacity, range: Shadow.opacities, name: "Opacity", set: { model.setShadowOpacity($0) })
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
                    pickCustom: { model.pickBorderColor($0) }
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
            onEditingChanged: { model.setDraggingStyle($0) }
        )
        .frame(height: 30)
        .accessibilityLabel(Text(name))
    }
}

/// A preset: a picture of the target with it on, or a plain card's, over its name.
private struct StyleTile: View {
    let title: String
    let selected: Bool
    /// Whether the arrow keys are on it.
    let highlighted: Bool
    let picture: CGImage?
    /// Called with true as the pointer moves onto the tile and false as it leaves.
    let preview: (Bool) -> Void
    let action: () -> Void
    let swatch: Swatch
    @State private var hovering = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Group {
                    if let picture {
                        Image(decorative: picture, scale: displayScale)
                    } else {
                        swatch.frame(width: 24, height: 16)
                    }
                }
                .frame(width: 48, height: 28)
                Text(title).font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Brutal.ink)
            .frame(width: 56, height: 52)
            .background {
                if selected {
                    PartyColor(Brutal.sky) { Color.clear.brutalSurface($0, radius: 7, shadow: 2) }
                } else if hovering || highlighted {
                    RoundedRectangle(cornerRadius: 7, style: .circular).fill(Brutal.ink.opacity(0.08))
                }
            }
            .overlay {
                if highlighted, !selected {
                    Color.clear.inkBorder(RoundedRectangle(cornerRadius: 7, style: .circular), width: 1)
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

/// Use this style for new captures: saves the screenshot's style for new captures to open and copy with.
private struct NewCaptureStyleSwitch: View {
    let model: EditorModel

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Use this style for new captures", isOn: Binding(get: { model.usesStyleForNewCaptures }, set: { model.setUsesStyleForNewCaptures($0) }))
                .toggleStyle(BrutalToggleStyle(color: Brutal.mint))
                .labelsHidden()
            Text("Use this style for new captures")
                .font(Brutal.caption)
                .foregroundStyle(Brutal.ink)
        }
        .brutalTip("New captures open and copy with this screenshot's style")
    }
}
