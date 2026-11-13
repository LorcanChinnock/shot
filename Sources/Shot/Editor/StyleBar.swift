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
    var sizesText: Bool { get }
    var paletteColorRows: [StyleBarColorRow] { get }
    var paletteControlRows: [[StyleBarControl]] { get }
    var paletteColor: RGBA { get set }
    var paletteFill: RGBA? { get set }
    var paletteNoteTextColor: RGBA? { get }
    func setNoteTextColor(_ color: RGBA?)
    var paletteShownSize: CGFloat { get }
    func canStepLineWidth(by steps: Int) -> Bool
    func stepLineWidth(by steps: Int)
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
    func lastCustomNoteText() -> RGBA?
    func pickCustomNoteText(_ color: RGBA)
    func beginColorPick()
    var canResetToolOptions: Bool { get }
    func resetToolOptions()
    func setDraggingStyle(_ dragging: Bool)
}

extension EditorModel: StyleBarEditing {}

/// The bar. On the left, a row of colours for each colour the mark has, named on its left: Line, and Fill under it for a
/// shape; Text, and Background under it for a note. Each row has the seven colours, a custom one and transparent. On the
/// right, the width or text size, a shape's outlines and a text's alignment. A redaction and a spotlight show all their
/// options in one row in place of the colours. Right-clicking it offers Reset Style, as the Edit menu does. The video
/// editor shows it too, at the top of the video's well.
struct StyleBar<Model: StyleBarEditing>: View {
    @Bindable var model: Model
    let content: StyleBarContent
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular)
        HStack(alignment: .top, spacing: 8) {
            switch content {
            case .colorAndWidth: colorAndWidth
            case .redaction: redaction
            case .spotlight: spotlight
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

    /// The colour rows in a grid, so their swatches line up after names of any length, then a divider as tall as the bar
    /// and the other controls.
    @ViewBuilder private var colorAndWidth: some View {
        let rows = model.paletteColorRows
        let controls = model.paletteControlRows
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: rowSpacing) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    rowLabel(rows[index])
                    colorRow(rows[index])
                }
            }
        }
        StyleBarDivider(rows: max(rows.count, controls.count))
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(controls.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    ForEach(controls[index].indices, id: \.self) { position in
                        control(controls[index][position])
                    }
                }
            }
        }
    }

    @ViewBuilder private func control(_ control: StyleBarControl) -> some View {
        switch control {
        case .width:
            stepper
        case .outline:
            if let shape = model.paletteShape {
                GlyphSegmented(selection: shape, options: BoxShape.allCases.map { ($0, $0.title) }, choose: model.setShape) { shape, selected in
                    StyleBarGlyph(symbol: shape.symbol, selected: selected)
                }
                .accessibilityLabel(Text("Shape"))
            }
        case .alignment:
            if let alignment = model.paletteAlignment {
                GlyphSegmented(selection: alignment, options: TextAlign.allCases.map { ($0, $0.title) }, choose: model.setAlignment) { alignment, selected in
                    StyleBarGlyph(symbol: alignment.symbol, selected: selected)
                }
                .accessibilityLabel(Text("Alignment"))
            }
        case .verticalAlignment:
            if let vertical = model.paletteVerticalAlignment {
                GlyphSegmented(
                    selection: vertical, options: VerticalTextAlign.allCases.map { ($0, $0.title) }, choose: model.setVerticalAlignment
                ) { vertical, selected in
                    StyleBarGlyph(symbol: vertical.symbol, selected: selected)
                }
                .accessibilityLabel(Text("Vertical alignment"))
            }
        }
    }

    @ViewBuilder private var redaction: some View {
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
    }

    @ViewBuilder private var spotlight: some View {
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

    private var labelColor: ContrastAware { ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink) }

    /// One colour row: the seven colours, the custom one, then transparent. A note's text has none chosen while it's black
    /// or white to suit the paper, and clicking its chosen colour again goes back to that.
    @ViewBuilder private func colorRow(_ row: StyleBarColorRow) -> some View {
        switch row {
        case .line, .text, .paper, .counter:
            swatches(selected: model.paletteColor, clear: .clear, help: String(localized: "Custom colour"), lastCustom: model.lastCustom(forFill: false)) {
                model.paletteColor = $0 ?? .clear
            } pickCustom: {
                model.pickCustom($0, forFill: false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(row.title))
        case .fill:
            swatches(selected: model.paletteFill, clear: nil, help: String(localized: "Custom fill colour"), lastCustom: model.lastCustom(forFill: true)) {
                model.paletteFill = $0
            } pickCustom: {
                model.pickCustom($0, forFill: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(row.title))
        case .noteText:
            let chosen = model.paletteNoteTextColor
            swatches(selected: chosen, clear: .clear, help: String(localized: "Custom colour"), lastCustom: model.lastCustomNoteText(), matchesNone: false) { color in
                model.setNoteTextColor(color == chosen ? nil : color)
            } pickCustom: {
                model.pickCustomNoteText($0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(row.title))
            .accessibilityValue(chosen == nil ? Text("Automatic") : Text(verbatim: ""))
        }
    }

    /// The row's name. A note's text explains, on pointing at it, what no colour chosen means.
    @ViewBuilder private func rowLabel(_ row: StyleBarColorRow) -> some View {
        let label = Text(row.title).font(Theme.small).foregroundStyle(labelColor).accessibilityHidden(true)
        if row == .noteText {
            label.themeTip(
                row.title,
                detail: String(localized: "With no colour chosen, the text is black or white, whichever reads better on the paper. Click the chosen colour again to go back to that.")
            )
        } else {
            label
        }
    }

    /// The preset colours, the rainbow swatch for a custom one, then transparent, which sets `clear`. `selected` is the
    /// colour shown; with `matchesNone` off, a `nil` one shows no swatch chosen rather than transparent.
    private func swatches(
        selected: RGBA?, clear: RGBA?, help: String, lastCustom: RGBA?, matchesNone: Bool = true,
        choose: @escaping (RGBA?) -> Void, pickCustom: @escaping (RGBA) -> Void
    ) -> some View {
        let isClear = selected.map { $0.a == 0 } ?? matchesNone
        return HStack(spacing: 8) {
            ForEach(StyleBarSwatches.colors.indices, id: \.self) { index in
                let color = StyleBarSwatches.colors[index]
                StyleBarSwatch(color: color, name: PresetColorNames.all[index], selected: selected == color) {
                    choose(color)
                }
            }
            CustomColorButton(
                custom: selected.flatMap { StyleBarSwatches.contains($0) || $0.a == 0 ? nil : $0 },
                lastCustom: lastCustom,
                fallback: selected.flatMap { $0.a == 0 ? nil : $0 } ?? RGBA(1, 1, 1),
                help: help,
                pick: pickCustom,
                beginPicking: model.beginColorPick,
                editorShown: { _ in },
                compact: true
            )
            StyleBarSwatch(color: nil, name: String(localized: "Transparent"), selected: isClear) { choose(clear) }
        }
        .frame(height: 24)
    }

    /// Thinner and thicker, or smaller and larger for text, with the width or text size between them.
    private var stepper: some View {
        let sizesText = model.sizesText
        return StyleBarStepper(
            value: model.paletteShownSize,
            label: sizesText ? String(localized: "Text size") : String(localized: "Line width"),
            down: sizesText ? String(localized: "Smaller") : String(localized: "Thinner"),
            up: sizesText ? String(localized: "Larger") : String(localized: "Thicker"),
            canStep: model.canStepLineWidth(by:),
            step: model.stepLineWidth(by:)
        )
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

/// The space between the bar's rows.
private let rowSpacing: CGFloat = 8

extension StyleBarColorRow {
    /// The name on the row's left.
    var title: String {
        switch self {
        case .line: String(localized: "Line")
        case .fill, .counter: String(localized: "Fill")
        case .text, .noteText: String(localized: "Text")
        case .paper: String(localized: "Background")
        }
    }
}

/// Down and up arrows on the segmented control's track with the value between them, from the thinnest width or smallest
/// size to the largest. With either arrow focused, the arrow keys step it too. VoiceOver reads it as one adjustable
/// control.
private struct StyleBarStepper: View {
    let value: CGFloat
    let label: String
    let down: String
    let up: String
    let canStep: (Int) -> Bool
    let step: (Int) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    private var shown: String { Double(value).formatted(.number.precision(.fractionLength(0...1))) }

    var body: some View {
        let track = RoundedRectangle(cornerRadius: 8, style: .circular)
        HStack(spacing: 0) {
            arrow("chevron.down", help: down, by: -1)
            Text(verbatim: shown)
                .font(.scaled(11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(StyleBarGlyph.color(selected: true))
                .frame(minWidth: 26)
            arrow("chevron.up", help: up, by: 1)
        }
        .padding(2)
        .background(Theme.fieldFill, in: track)
        .overlay {
            if contrast == .increased {
                Color.clear.inkBorder(track, width: 1, color: Theme.ink.opacity(0.6))
            }
        }
        .onKeyPress(keys: [.upArrow, .rightArrow, .downArrow, .leftArrow], phases: [.down, .repeat]) { press in
            step(press.key == .upArrow || press.key == .rightArrow ? 1 : -1)
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: shown))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    private func arrow(_ symbol: String, help: String, by steps: Int) -> some View {
        Button {
            step(steps)
        } label: {
            StyleBarGlyph(symbol: symbol, selected: false)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.halo(radius: 6))
        .disabled(!canStep(steps))
        .opacity(canStep(steps) ? 1 : 0.35)
        .themeTip(help)
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

/// A 1 pt rule between parts of the bar, 3 pt short of the top and bottom of the `rows` it stands beside.
private struct StyleBarDivider: View {
    var rows = 1

    var body: some View {
        Rectangle()
            .fill(Theme.controlEdge)
            .frame(width: 1, height: CGFloat(rows) * 24 + CGFloat(rows - 1) * rowSpacing - 6)
            .padding(.vertical, 3)
            .accessibilityHidden(true)
    }
}

/// A 20 pt colour. The chosen one has an ink ring outside a gap of the bar's colour; the others a faint edge, so white
/// marks and black on dark still show their shape. A `nil` colour is transparent, drawn as a grey and white check.
private struct StyleBarSwatch: View {
    let color: RGBA?
    let name: String
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    private static let edge = Color(light: .black.opacity(0.12), dark: .white.opacity(0.18))

    var body: some View {
        Button(action: action) {
            Group {
                if let color {
                    Circle().fill(color.swiftUIColor)
                } else {
                    Checkerboard().clipShape(Circle())
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
