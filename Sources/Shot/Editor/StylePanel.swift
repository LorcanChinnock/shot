import ShotCore
import SwiftUI

/// The Style panel beside the canvas, from Edit › Image editor · style. With nothing selected it styles the screenshot:
/// its background, padding, corners, shadow, border and size, and whether new captures start that way. With an image,
/// shape, arrow or text selected, that selection's corners, shadow and border come first, and the canvas's background,
/// padding and size follow. Pointing at a shadow or border tile shows it on the canvas; clicking it applies it.
struct StylePanel: View {
    @Bindable var model: EditorModel

    static let width: CGFloat = 288
    /// The panel's width less its 16 pt sides, which the sliders fill.
    private static let inner: CGFloat = width - 32

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let kind = model.targetStyleKind
        let sections = StylePanelLayout.sections(
            kind: kind, windowShadow: model.targetHasWindowShadow,
            borders: kind.map { !$0.borders(transparent: model.targetHasTransparency).isEmpty } ?? false
        )
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if kind != nil, kind != .capture {
                        groupTitle(Text(verbatim: kind?.panelTitle ?? ""))
                    }
                    ForEach(sections.target.filter { $0 != .newCaptures }, id: \.self) { section(for: $0) }
                    if !sections.canvas.isEmpty {
                        Divider().overlay(Brutal.separator)
                        groupTitle(Text("Canvas"))
                        ForEach(sections.canvas, id: \.self) { section(for: $0) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
            if sections.target.contains(.newCaptures), let newCaptureStyle = model.newCaptureStyle {
                NewCaptureCard(isOn: newCaptureStyle, otherStyleSaved: model.newCapturesHaveOtherStyle)
                    .padding([.horizontal, .bottom], 16)
                    .padding(.top, 4)
            }
        }
        .frame(width: Self.width)
        .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular))
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Style"))
        .onDisappear {
            model.stylePreview = nil
        }
    }

    private var increased: Bool { contrast == .increased }

    /// "Style" in 13 pt bold, and Reset as an accent-text link that greys out when there's nothing to put back.
    private var header: some View {
        HStack {
            Text("Style")
                .font(.scaled(13, weight: .bold))
                .foregroundStyle(Brutal.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("Reset") { model.resetTargetStyle() }
                .buttonStyle(PanelLinkStyle())
                .disabled(model.isTargetStyleDefault)
                .brutalTip("Reset", detail: resetDetail)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var resetDetail: LocalizedStringResource {
        model.targetStyleKind == .capture
            ? "Puts the screenshot's background, padding, size, shadow, border and corners back to how a new capture starts."
            : "Puts the selection's shadow, border and corners back to how new ones start."
    }

    private func groupTitle(_ text: Text) -> some View {
        text
            .font(.scaled(12, weight: .bold))
            .foregroundStyle(Brutal.ink)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func section(for section: StylePanelLayout.Section) -> some View {
        switch section {
        case .background: backgroundSection
        case .padding: paddingSection
        case .corners: cornersSection
        case .shadow: shadowSection
        case .border: borderSection
        case .size: sizeSection
        case .windowShadowNote:
            note("Uses macOS window shadow")
                .brutalTip("This window was captured with its own shadow, so it takes no other shadow, border or corners")
        case .noTargetNote:
            note("Select an image, shape, arrow or text, or nothing to style the screenshot.")
        case .newCaptures:
            EmptyView()
        }
    }

    private func note(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(Brutal.caption)
            .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func heading(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.scaled(11.5, weight: .semibold))
            .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Background

    /// None, the panel's seven colours, three gradients, the desktop picture and a custom colour, 7 to a row.
    private var backgroundSection: some View {
        let doc = model.document
        let fill = doc.backgroundFill
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(alignment: .leading, spacing: 8) {
            heading("Background")
            LazyVGrid(columns: columns, spacing: 6) {
                BackgroundTile(name: String(localized: "None"), selected: fill == nil && doc.background == nil) {
                    model.setBackground(nil)
                } swatch: {
                    Checkerboard()
                }
                // JPEG has no alpha, so it can't keep transparent padding.
                .disabled(model.isJPEG)
                ForEach(BackgroundSwatches.colors.indices, id: \.self) { index in
                    let swatch = BackgroundSwatches.colors[index]
                    BackgroundTile(name: swatch.name, selected: fill == nil && doc.background == swatch.color) {
                        model.setBackground(swatch.color)
                    } swatch: {
                        swatch.color.swiftUIColor
                    }
                }
                ForEach(BackgroundFill.allCases, id: \.self) { gradient in
                    BackgroundTile(name: gradient.title, selected: fill == gradient) {
                        model.setBackgroundFill(gradient)
                    } swatch: {
                        GradientSwatch(fill: gradient, picture: gradient == .desktop ? doc.desktopPicture : nil)
                    }
                }
                CustomBackgroundTile(model: model)
            }
        }
    }

    // MARK: Padding and corners

    private var paddingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRow(
                "Padding", value: model.canvasPadding, range: CanvasFrame.paddings, shown: "\(Int(model.canvasPadding.rounded())) pt",
                set: { model.setCanvasPadding($0) }
            )
            if model.targetStyleKind == .capture, !model.targetHasWindowShadow {
                cornersSlider
            }
        }
    }

    /// The selection's corners, on its own when the target isn't the screenshot, whose corners sit under its padding.
    @ViewBuilder
    private var cornersSection: some View {
        if model.targetStyleKind != .capture {
            cornersSlider
        }
    }

    private var cornersSlider: some View {
        sliderRow(
            "Corners", value: model.targetCornerRadius, range: 0...48, shown: "\(Int(model.targetCornerRadius.rounded())) pt",
            set: { model.setTargetCornerRadius($0) }
        )
    }

    /// The name and value over a slider as wide as the panel.
    private func sliderRow(_ name: LocalizedStringResource, value: CGFloat, range: ClosedRange<CGFloat>, shown: String, set: @escaping (CGFloat) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                Spacer(minLength: 8)
                Text(verbatim: shown)
                    .font(.scaled(12, tabular: true))
                    .foregroundStyle(Brutal.ink)
            }
            .accessibilityHidden(true)
            BrutalSlider(
                value: Binding(get: { Double(value) }, set: { set(CGFloat($0)) }),
                range: Double(range.lowerBound)...Double(range.upperBound),
                width: Self.inner,
                onEditingChanged: { model.setDraggingStyle($0) }
            )
            .frame(height: 18)
            .accessibilityLabel(Text(name))
            .accessibilityValue(Text(verbatim: shown))
        }
    }

    // MARK: Shadow and border

    private var shadowSection: some View {
        let style = model.targetStyle
        let shadows: [PanelPreset] = [PanelPreset(id: "shadow-none", title: String(localized: "None"), style: with(style) { $0.shadow = nil }, selected: style.shadow == nil, swatch: StylePresetSwatch())]
            + ShadowPreset.allCases.map { preset in
                let shadow = preset.shadow(scale: model.scale)
                return PanelPreset(id: "shadow-\(preset.rawValue)", title: preset.title, style: with(style) { $0.shadow = shadow }, selected: style.shadow == shadow, swatch: StylePresetSwatch(shadow: preset))
            }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                heading("Shadow")
                if let shadow = style.shadow, ShadowPreset.matching(shadow, scale: model.scale) == nil {
                    BrutalBadge(text: "CUSTOM")
                }
            }
            presetGrid(shadows)
            if let shadow = style.shadow {
                sliderRow(
                    "Elevation", value: shadow.elevation / model.scale, range: Shadow.elevations, shown: "\(Int((shadow.elevation / model.scale).rounded())) pt",
                    set: { model.setShadowElevation($0) }
                )
                sliderRow(
                    "Opacity", value: shadow.opacity, range: Shadow.opacities, shown: "\(Int((shadow.opacity * 100).rounded()))%",
                    set: { model.setShadowOpacity($0) }
                )
            }
        }
    }

    private var borderSection: some View {
        let style = model.targetStyle
        let kinds = model.targetStyleKind?.borders(transparent: model.targetHasTransparency) ?? []
        let borders: [PanelPreset] = [PanelPreset(id: "border-none", title: String(localized: "None"), style: with(style) { $0.border = nil }, selected: style.border == nil, swatch: StylePresetSwatch())]
            + kinds.map { kind in
                let border = model.newBorder(kind)
                return PanelPreset(id: "border-\(kind.rawValue)", title: kind.title, style: with(style) { $0.border = border }, selected: style.border?.kind == kind, swatch: StylePresetSwatch(border: kind))
            }
        return VStack(alignment: .leading, spacing: 8) {
            heading("Border")
            presetGrid(borders)
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

    private func presetGrid(_ presets: [PanelPreset]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(presets) { preset in
                PresetTile(preset: preset, model: model)
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

    // MARK: Size

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Size")
            BrutalSegmented(
                selection: Binding(get: { model.document.frame.aspect }, set: { model.setCanvasAspect($0) }),
                options: CanvasAspect.allCases.map { (value: $0, label: $0.title) }
            )
            .fillingWidth()
            .accessibilityLabel(Text("Size"))
        }
    }
}

extension StyleKind {
    /// The heading over a selection's own part of the Style panel.
    var panelTitle: String {
        switch self {
        case .capture: String(localized: "Screenshot")
        case .image: String(localized: "Selected image")
        case .mark: String(localized: "Selected shape")
        case .text: String(localized: "Selected text")
        }
    }
}

/// A shadow or border tile: the target's style with one change made to it.
private struct PanelPreset: Identifiable {
    let id: String
    let title: String
    let style: ObjectStyle
    let selected: Bool
    let swatch: StylePresetSwatch
}

/// A card with the preset's look over its name. The chosen one is white with a 1.5 pt ink edge, as on the board.
/// Pointing at it shows it on the canvas until the pointer moves off.
private struct PresetTile: View {
    let preset: PanelPreset
    let model: EditorModel
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

/// A square background swatch. The chosen one has a 1.5 pt ink ring outside a 2 pt gap; the others an inner edge.
private struct BackgroundTile<Swatch: View>: View {
    let name: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let swatch: Swatch
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            BackgroundSwatchShape(selected: selected) { swatch }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .brutalTip(name)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The swatch's square, its edge and the ring that marks it chosen.
private struct BackgroundSwatchShape<Content: View>: View {
    let selected: Bool
    @ViewBuilder let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brutal.Radius.control, style: .circular)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .clipShape(shape)
            .overlay {
                if contrast == .increased {
                    Color.clear.inkBorder(shape, width: 1, color: Brutal.ink.opacity(0.6))
                } else {
                    shape.strokeBorder(backgroundSwatchEdge, lineWidth: 1)
                }
            }
            .padding(3.5)
            .overlay {
                if selected {
                    // The text colour rather than the ink line, which disappears on the dark panel.
                    Color.clear.inkBorder(RoundedRectangle(cornerRadius: Brutal.Radius.control + 3.5, style: .circular), width: 1.5, color: Brutal.ink)
                }
            }
            .padding(-3.5)
            .contentShape(Rectangle())
    }
}

/// A background swatch's inner edge: ink at 12%, or white at 18% in dark.
private let backgroundSwatchEdge = Color(light: Color(hex: 0x16161A).opacity(0.12), dark: .white.opacity(0.18))

/// A gradient swatch, or the desktop picture itself once it's read.
private struct GradientSwatch: View {
    let fill: BackgroundFill
    let picture: CGImage?

    var body: some View {
        if let picture {
            Image(decorative: picture, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            let (start, end) = fill.colors
            LinearGradient(
                colors: [start.swiftUIColor, end.swiftUIColor],
                startPoint: .topLeading, endPoint: fill.isVertical ? .bottomLeading : .bottomTrailing
            )
        }
    }
}

/// The see-through background: a grey and white check, 5 pt squares.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let side: CGFloat = 5
            for row in 0..<Int(ceil(size.height / side)) {
                for column in 0..<Int(ceil(size.width / side)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)), with: .color(Color(hex: 0xE4E2DD)))
                }
            }
        }
    }
}

/// A rainbow swatch for any other colour. It applies the last custom colour and opens the colour editor on it, which
/// shows the colour inside the rainbow while it's in use.
private struct CustomBackgroundTile: View {
    @Bindable var model: EditorModel
    @State private var isOpen = false

    private var custom: RGBA? {
        let doc = model.document
        guard doc.backgroundFill == nil, let background = doc.background, !BackgroundSwatches.contains(background) else {
            return nil
        }
        return background
    }

    var body: some View {
        Button(action: open) {
            BackgroundSwatchShape(selected: custom != nil || isOpen) {
                ZStack {
                    AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)
                    if let custom {
                        RoundedRectangle(cornerRadius: 3, style: .circular).fill(custom.swiftUIColor).padding(6)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .brutalTip("Custom background colour")
        .accessibilityLabel(Text("Custom background colour"))
        .accessibilityAddTraits(custom != nil ? .isSelected : [])
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ColorEditor(initial: model.lastBackgroundColor ?? custom ?? RGBA(1, 1, 1), pick: model.pickBackground)
        }
    }

    private func open() {
        guard !isOpen else {
            isOpen = false
            return
        }
        model.beginColorPick()
        if let last = model.lastBackgroundColor, last != custom {
            model.pickBackground(last)
        }
        isOpen = true
    }
}

/// Use for new captures, on a white card at the panel's foot. Off while new captures still get another saved style
/// says so, since the switch alone reads as "new captures are plain".
private struct NewCaptureCard: View {
    let isOn: Binding<Bool>
    let otherStyleSaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Use for new captures")
                    .font(.scaled(12.5))
                    .foregroundStyle(Brutal.ink)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Toggle("Use for new captures", isOn: isOn)
                    .toggleStyle(BrutalToggleStyle())
                    .labelsHidden()
                    .accessibilityLabel(Text("Use for new captures"))
            }
            if otherStyleSaved {
                Text("New captures keep a different saved style.")
                    .font(Brutal.caption)
                    .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .depth(.rest, fill: Brutal.group, radius: Brutal.Radius.group)
        .brutalTip("Use for new captures", detail: "New captures open and copy with this screenshot's background, padding, size, shadow, border and corners.")
    }
}

/// Reset in the panel's header: 12 pt medium accent text, faded when there's nothing to reset.
private struct PanelLinkStyle: ButtonStyle {
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
