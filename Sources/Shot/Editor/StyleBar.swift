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
    }
}

/// What the style bar edits: the drawing options of the image editor or the video editor, which both build them from
/// ShotCore's `AnnotationPalette`.
@MainActor
protocol StyleBarEditing: AnyObject, Observable {
    var showsStyle: Bool { get }
    var sizesText: Bool { get }
    var showsFill: Bool { get }
    var paletteColor: RGBA { get set }
    var paletteFill: RGBA? { get set }
    var lineWidthIndex: Int { get set }
    var paletteShape: BoxShape? { get }
    func setShape(_ shape: BoxShape)
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

/// The bar: the seven colours and a custom one, a divider and the three widths. A shape adds a second row of its five
/// outlines and its fill, and a text or a note one of its alignment. A redaction and a spotlight show all their options
/// in one row in place of the colours. Right-clicking it offers Reset Style, as the Edit menu does. The video editor
/// shows it too, at the top of the video's well.
struct StyleBar<Model: StyleBarEditing>: View {
    @Bindable var model: Model
    let content: StyleBarContent
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                firstRow
            }
            if content.hasSecondRow(hasShape: model.paletteShape != nil, hasFill: model.showsFill, hasAlignment: model.paletteAlignment != nil) {
                HStack(spacing: 8) {
                    secondRow
                }
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

    @ViewBuilder private var firstRow: some View {
        switch content {
        case .colorAndWidth:
            swatches(selected: model.paletteColor, forFill: false, help: String(localized: "Custom colour")) { color in
                if let color {
                    model.paletteColor = color
                }
            }
            StyleBarDivider()
            widths
        case .redaction:
            if let redaction = model.paletteRedaction {
                GlyphSegmented(
                    selection: redaction, options: Redaction.allCases.map { ($0, $0.title) }, choose: model.setRedaction
                ) { redaction, selected in
                    StyleBarGlyph(symbol: redaction == .blur ? "drop.halffull" : "square.grid.3x3", selected: selected)
                }
                .accessibilityLabel(Text("Blur or pixelate"))
                StyleBarDivider()
                slider("Amount", value: model.paletteRedactionAmount, range: Redaction.amounts.lowerBound...Redaction.amounts.upperBound) {
                    model.setRedactionAmount($0)
                }
                .themeTip("Amount")
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
                StyleBarDivider()
                slider("Strength", value: spotlight.strength, range: SpotlightStyle.strengths) {
                    model.setSpotlightLook(effect: spotlight.effect, strength: $0)
                }
                .themeTip("Strength", detail: "Applies to every spotlight in the image.")
                StyleBarDivider()
                slider("Soft edge", value: spotlight.softEdge, range: 0...1, set: model.setSpotlightSoftEdge)
                    .themeTip("Soft edge", detail: "Fades the spotlight into the dim.")
            }
        }
    }

    /// A shape's outlines and fill, or a text's alignment and a note's place top to bottom.
    @ViewBuilder private var secondRow: some View {
        if let shape = model.paletteShape {
            GlyphSegmented(selection: shape, options: BoxShape.allCases.map { ($0, $0.title) }, choose: model.setShape) { shape, selected in
                StyleBarGlyph(symbol: shape.symbol, selected: selected)
            }
            .accessibilityLabel(Text("Shape"))
        }
        if model.showsFill {
            if model.paletteShape != nil {
                StyleBarDivider()
            }
            fill
        }
        if let alignment = model.paletteAlignment {
            if model.paletteShape != nil || model.showsFill {
                StyleBarDivider()
            }
            GlyphSegmented(selection: alignment, options: TextAlign.allCases.map { ($0, $0.title) }, choose: model.setAlignment) { alignment, selected in
                StyleBarGlyph(symbol: alignment.symbol, selected: selected)
            }
            .accessibilityLabel(Text("Alignment"))
            if let vertical = model.paletteVerticalAlignment {
                StyleBarDivider()
                GlyphSegmented(
                    selection: vertical, options: VerticalTextAlign.allCases.map { ($0, $0.title) }, choose: model.setVerticalAlignment
                ) { vertical, selected in
                    StyleBarGlyph(symbol: vertical.symbol, selected: selected)
                }
                .accessibilityLabel(Text("Vertical alignment"))
            }
        }
    }

    /// "Fill" ahead of its swatches, so they can't be taken for the colours above them.
    private var fill: some View {
        HStack(spacing: 8) {
            Text("Fill").font(Theme.small).foregroundStyle(labelColor).accessibilityHidden(true)
            swatches(selected: model.paletteFill, allowsNone: true, forFill: true, help: String(localized: "Custom fill colour")) {
                model.paletteFill = $0
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Fill"))
    }

    private var labelColor: ContrastAware { ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink) }

    /// The preset colours, then the rainbow swatch for a custom one. With `allowsNone`, a first swatch clears the colour.
    private func swatches(selected: RGBA?, allowsNone: Bool = false, forFill: Bool, help: String, choose: @escaping (RGBA?) -> Void) -> some View {
        HStack(spacing: 8) {
            if allowsNone {
                StyleBarSwatch(color: nil, name: String(localized: "Transparent"), selected: selected == nil) { choose(nil) }
            }
            ForEach(StyleBarSwatches.colors.indices, id: \.self) { index in
                let color = StyleBarSwatches.colors[index]
                StyleBarSwatch(color: color, name: PresetColorNames.all[index], selected: selected == color) {
                    choose(color)
                }
            }
            CustomColorButton(
                custom: selected.flatMap { StyleBarSwatches.contains($0) ? nil : $0 },
                lastCustom: model.lastCustom(forFill: forFill),
                fallback: selected ?? RGBA(1, 1, 1),
                help: help,
                pick: { model.pickCustom($0, forFill: forFill) },
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

    /// A short slider with its name ahead of it, as tall as the bar's segmented controls.
    private func slider(_ title: LocalizedStringResource, value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(Theme.small).foregroundStyle(labelColor).accessibilityHidden(true)
            ThemeSlider(value: Binding(get: { value }, set: set), range: range, width: 72, onEditingChanged: model.setDraggingStyle)
                .frame(height: 24)
                .accessibilityLabel(Text(title))
        }
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
/// marks and black on dark still show their shape. A `nil` colour is none, drawn as paper struck through in red.
private struct StyleBarSwatch: View {
    let color: RGBA?
    let name: String
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    private static let edge = Color(light: .black.opacity(0.12), dark: .white.opacity(0.18))

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color?.swiftUIColor ?? Theme.paper)
                .overlay {
                    if color == nil {
                        Rectangle().fill(Theme.red).frame(width: 1.5, height: 20).rotationEffect(.degrees(45)).clipShape(Circle())
                    }
                }
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
