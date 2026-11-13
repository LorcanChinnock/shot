import ShotCore
import SwiftUI

/// Lays the style bar over the canvas, from Edit › Image editor · annotate: beside the mark it styles, or at the top for
/// the tool's next mark, and out of the way while a drag draws or moves. `StyleBarPlacement` decides where.
struct StyleBarOverlay: View {
    @Bindable var model: EditorModel
    @State private var barSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var content: StyleBarContent? { model.isCanvasDragging ? nil : model.styleBarContent }

    var body: some View {
        GeometryReader { proxy in
            if let content {
                let origin = StyleBarPlacement.origin(
                    bar: barSize, mark: model.styleBarMark, in: proxy.size, bottom: model.canvasFootHeight
                )
                StyleBar(model: model, content: content)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self, of: \.size) { barSize = $0 }
                    // Hidden for the one layout before its size is known, so it never shows in the wrong place.
                    .opacity(barSize == .zero ? 0 : 1)
                    .offset(x: origin.x, y: origin.y)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        // Arriving is the panel moment; following the mark as it moves stays instant, as every edit is.
        .animation(Motion.animation(.panelArrive, reduceMotion: reduceMotion), value: content)
        .onChange(of: content) {
            if content == nil {
                model.showsMoreStyle = false
            }
        }
    }
}

/// What the style bar edits: the drawing options of the image editor or the video editor, which both build them from
/// ShotCore's `AnnotationPalette`.
@MainActor
protocol StyleBarEditing: AnyObject, Observable {
    /// Whether More style, the bar's popover of the options that don't fit in it, is open.
    var showsMoreStyle: Bool { get set }
    var showsStyle: Bool { get }
    var sizesText: Bool { get }
    var showsFill: Bool { get }
    var paletteColor: RGBA { get set }
    var paletteFill: RGBA? { get set }
    var lineWidthIndex: Int { get set }
    var paletteShape: BoxShape? { get }
    func setShape(_ shape: BoxShape)
    var palettePenLine: PenLine? { get }
    func setPenLine(_ penLine: PenLine)
    var paletteRedaction: Redaction? { get }
    func setRedaction(_ redaction: Redaction)
    var paletteRedactionAmount: CGFloat { get }
    func setRedactionAmount(_ amount: CGFloat)
    var paletteSpotlight: SpotlightStyle? { get }
    func setSpotlightShape(_ shape: BoxShape)
    func setSpotlightLook(effect: SpotlightStyle.Effect, strength: Double)
    func setSpotlightSoftEdge(_ softEdge: Double)
    var paletteAlignment: TextAlign? { get }
    func setAlignment(_ alignment: TextAlign)
    var paletteVerticalAlignment: VerticalTextAlign? { get }
    func setVerticalAlignment(_ alignment: VerticalTextAlign)
    func lastCustom(forFill: Bool) -> RGBA?
    func pickCustom(_ color: RGBA, forFill: Bool)
    func beginColorPick()
    var canResetToolOptions: Bool { get }
    func resetToolOptions()
    func setDraggingStyle(_ dragging: Bool)
}

extension EditorModel: StyleBarEditing {}

/// The bar: the seven colours and a custom one, a divider and the three widths, rectangle or ellipse for a shape, smooth
/// or as drawn for the pen, then
/// More style for a mark's other options.
/// Right-clicking it offers Reset Style, as the Edit menu does. A redaction and a
/// spotlight show their own main choices in its place. The video editor shows it too, at the top of the video's well.
struct StyleBar<Model: StyleBarEditing>: View {
    @Bindable var model: Model
    let content: StyleBarContent
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular)
        HStack(spacing: 8) {
            switch content {
            case .colorAndWidth:
                swatches
                StyleBarDivider()
                widths
                if let shape = model.paletteShape {
                    StyleBarDivider()
                    GlyphSegmented(
                        selection: shape, options: BoxShape.styleBarShapes.map { ($0, $0.title) }, choose: model.setShape
                    ) { shape, selected in
                        StyleBarGlyph(symbol: shape.symbol, selected: selected)
                    }
                    .accessibilityLabel(Text("Shape"))
                }
                if let penLine = model.palettePenLine {
                    StyleBarDivider()
                    GlyphSegmented(
                        selection: penLine, options: PenLine.allCases.map { ($0, $0.title) }, choose: model.setPenLine
                    ) { penLine, selected in
                        StyleBarGlyph(symbol: penLine.symbol, selected: selected)
                    }
                    .accessibilityLabel(Text("Smooth or as drawn"))
                }
            case .redaction:
                if let redaction = model.paletteRedaction {
                    GlyphSegmented(
                        selection: redaction, options: Redaction.allCases.map { ($0, $0.title) }, choose: model.setRedaction
                    ) { redaction, selected in
                        StyleBarGlyph(symbol: redaction == .blur ? "drop.halffull" : "square.grid.3x3", selected: selected)
                    }
                    .accessibilityLabel(Text("Blur or pixelate"))
                }
            case .spotlight:
                if let spotlight = model.paletteSpotlight {
                    GlyphSegmented(
                        selection: spotlight.shape, options: BoxShape.spotlightShapes.map { ($0, $0.title) }, choose: model.setSpotlightShape
                    ) { shape, selected in
                        StyleBarGlyph(symbol: shape.symbol, selected: selected)
                    }
                    .accessibilityLabel(Text("Spotlight shape"))
                    StyleBarDivider()
                    GlyphSegmented(
                        selection: spotlight.effect,
                        options: SpotlightStyle.Effect.allCases.map { ($0, String(localized: "\($0.title) outside")) },
                        choose: { model.setSpotlightLook(effect: $0, strength: spotlight.strength) }
                    ) { effect, selected in
                        StyleBarGlyph(symbol: effect == .darken ? "moon.fill" : "drop.halffull", selected: selected)
                    }
                    .accessibilityLabel(Text("Outside the spotlight"))
                }
            }
            if content.offersMoreStyle(hasShape: model.paletteShape != nil, hasFill: model.showsFill, hasAlignment: model.paletteAlignment != nil) {
                MoreStyleButton(model: model)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .depth(.float, fill: solid ? AnyShapeStyle(Theme.group) : AnyShapeStyle(styleBarFill), radius: Theme.Radius.group)
        .overlay {
            if contrast == .increased {
                Color.clear.inkBorder(shape, width: 1, color: Theme.ink.opacity(0.6))
            }
        }
        .contentShape(shape)
        .contextMenu {
            Button("Reset Style", action: model.resetToolOptions)
                .disabled(!model.canResetToolOptions)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Style"))
    }

    private var solid: Bool { contrast == .increased || reduceTransparency }

    private var swatches: some View {
        HStack(spacing: 8) {
            ForEach(StyleBarSwatches.colors.indices, id: \.self) { index in
                let color = StyleBarSwatches.colors[index]
                StyleBarSwatch(color: color, name: PresetColorNames.all[index], selected: model.paletteColor == color) {
                    model.paletteColor = color
                }
            }
            CustomColorButton(
                custom: StyleBarSwatches.contains(model.paletteColor) ? nil : model.paletteColor,
                lastCustom: model.lastCustom(forFill: false),
                fallback: model.paletteColor,
                help: String(localized: "Custom colour"),
                pick: { model.pickCustom($0, forFill: false) },
                beginPicking: model.beginColorPick,
                editorShown: { _ in },
                compact: true
            )
        }
    }

    private var widths: some View {
        let sizesText = model.sizesText
        let names = sizesText ? WidthOptions.sizeNames : [String(localized: "Thin"), String(localized: "Medium"), String(localized: "Thick")]
        return GlyphSegmented(
            selection: model.lineWidthIndex,
            options: EditorStyle.widths.indices.map { ($0, names[$0]) },
            choose: { model.lineWidthIndex = $0 }
        ) { index, selected in
            let style = StyleBarGlyph.color(selected: selected)
            if sizesText {
                Text(verbatim: "A").font(.scaled(9 + CGFloat(index) * 2.5, weight: .bold)).foregroundStyle(style)
            } else {
                // 2, 4 and 6 pt lines, as on the board, for widths of 2, 4 and 8.
                Capsule().fill(style).frame(width: 12, height: CGFloat(index + 1) * 2)
            }
        }
        .accessibilityLabel(sizesText ? Text("Text size") : Text("Line width"))
    }
}

/// The board's fill, a touch see-through over the canvas.
private let styleBarFill = Color(light: .white.opacity(0.97), dark: Color(hex: 0x2C2C30).opacity(0.97))

/// A segmented control of pictures, which calls `choose` rather than holding a binding, as the palette's setters do.
private struct GlyphSegmented<Value: Hashable, Glyph: View>: View {
    let selection: Value
    let options: [(Value, String)]
    let choose: (Value) -> Void
    @ViewBuilder let glyph: (Value, Bool) -> Glyph

    var body: some View {
        ThemeSegmented(
            selection: Binding(get: { selection }, set: { choose($0) }),
            options: options.map { (value: $0.0, label: $0.1) },
            glyphSize: CGSize(width: 26, height: 20),
            glyph: glyph
        )
    }
}

/// An icon in a segment: ink when selected, else the toolbar's 85% ink.
private struct StyleBarGlyph: View {
    let symbol: String
    let selected: Bool

    var body: some View {
        Image(systemName: symbol).font(.scaled(11, weight: .semibold)).foregroundStyle(Self.color(selected: selected))
    }

    static func color(selected: Bool) -> ContrastAware {
        selected ? ContrastAware(standard: Theme.ink, increased: Theme.ink) : ContrastAware(standard: Theme.ink.opacity(0.85), increased: Theme.ink)
    }
}

private struct StyleBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.controlEdge)
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }
}

/// A 20 pt colour. The chosen one has an ink ring outside a gap of the bar's colour; the others a faint edge, so white
/// marks and black on dark still show their shape.
private struct StyleBarSwatch: View {
    let color: RGBA
    let name: String
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    private static let edge = Color(light: .black.opacity(0.12), dark: .white.opacity(0.18))

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.swiftUIColor)
                .overlay {
                    if !selected {
                        Circle().strokeBorder(Self.edge, lineWidth: 1)
                    }
                }
                .frame(width: 20, height: 20)
                .background {
                    if selected {
                        Color.clear.inkBorder(Circle(), width: 1.5, color: Theme.ink).padding(-3.5)
                    }
                }
                .background {
                    if focused {
                        Color.clear.inkBorder(Circle(), width: 4, color: Theme.focusRing).padding(selected ? -7.5 : -4)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focused)
        .themeTip(name)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "…": opens the options that don't fit in the bar, with Reset.
private struct MoreStyleButton<Model: StyleBarEditing>: View {
    @Bindable var model: Model

    var body: some View {
        Button {
            model.showsMoreStyle.toggle()
        } label: {
            Image(systemName: "ellipsis").font(Theme.toolIcon)
        }
        .buttonStyle(ThemeButtonStyle(.toolbar, isOn: model.showsMoreStyle))
        .accessibilityLabel(Text("More style"))
        .themeTip("More style", detail: "Shows the rest of this mark's options, such as its fill, and Reset.")
        .popover(isPresented: $model.showsMoreStyle, arrowEdge: .bottom) {
            MoreStyle(model: model)
        }
    }
}

/// What the bar has no room for: for a shape, its other outlines and its fill; for a mark, its fill and the text's alignment; for a redaction its amount; for a spotlight its strength and soft edge. Reset is last.
private struct MoreStyle<Model: StyleBarEditing>: View {
    @Bindable var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.showsStyle {
                if let shape = model.paletteShape {
                    row("More shapes") {
                        HStack(spacing: 4) {
                            ForEach(BoxShape.moreStyleShapes, id: \.self) { option in
                                Tile(selected: shape == option, help: option.title) {
                                    model.setShape(option)
                                } label: {
                                    Image(systemName: option.symbol).font(Theme.toolIcon)
                                }
                            }
                        }
                    }
                }
                if model.showsFill {
                    row("Fill") {
                        HStack(spacing: 0) {
                            ColorSwatches(
                                selected: model.paletteFill,
                                lastCustom: model.lastCustom(forFill: true),
                                allowsNone: true,
                                customHelp: "Custom fill colour",
                                choose: { model.paletteFill = $0 },
                                pickCustom: { model.pickCustom($0, forFill: true) },
                                beginPicking: model.beginColorPick
                            )
                        }
                    }
                }
                if let alignment = model.paletteAlignment {
                    row("Alignment") {
                        HStack(spacing: 4) {
                            ForEach(TextAlign.allCases, id: \.self) { option in
                                Tile(selected: alignment == option, help: option.title) {
                                    model.setAlignment(option)
                                } label: {
                                    Image(systemName: option.symbol).font(Theme.toolIcon)
                                }
                            }
                            if let vertical = model.paletteVerticalAlignment {
                                StyleBarDivider().padding(.horizontal, 2)
                                ForEach(VerticalTextAlign.allCases, id: \.self) { option in
                                    Tile(selected: vertical == option, help: option.title) {
                                        model.setVerticalAlignment(option)
                                    } label: {
                                        Image(systemName: option.symbol).font(Theme.toolIcon)
                                    }
                                }
                            }
                        }
                    }
                }
            } else if model.paletteRedaction != nil {
                row("Amount") {
                    slider(value: model.paletteRedactionAmount, range: Redaction.amounts.lowerBound...Redaction.amounts.upperBound) { model.setRedactionAmount($0) }
                        .accessibilityLabel(Text("Amount"))
                }
            } else if let spotlight = model.paletteSpotlight {
                row("Strength") {
                    slider(value: spotlight.strength, range: SpotlightStyle.strengths) { model.setSpotlightLook(effect: spotlight.effect, strength: $0) }
                        .accessibilityLabel(Text("Strength"))
                        .themeTip("Strength", detail: "Applies to every spotlight in the image.")
                }
                row("Soft edge") {
                    slider(value: spotlight.softEdge, range: 0...1, set: model.setSpotlightSoftEdge)
                        .accessibilityLabel(Text("Soft edge"))
                        .themeTip("Soft edge", detail: "Fades the spotlight into the dim.")
                }
            }
            Button("Reset", action: model.resetToolOptions)
                .buttonStyle(ThemeButtonStyle(.plain))
                .disabled(!model.canResetToolOptions)
                .themeTip("Reset", detail: "Puts this tool's colour, size and other options back to how a new install starts. Your saved custom colours stay.")
        }
        .padding(14)
        .frame(minWidth: 240, alignment: .leading)
    }

    private func row<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.small).foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
            content()
        }
    }

    private func slider(value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        ThemeSlider(value: Binding(get: { value }, set: set), range: range, width: 200, onEditingChanged: model.setDraggingStyle)
            .frame(height: 24)
    }
}
