import ShotCore
import SwiftUI

struct EditorToolbar: View {
    /// Matches `RGBA.presets`.
    static let colorNames = ["Red", "Orange", "Yellow", "Green", "Blue", "Black", "White"]

    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ToolGroup {
                    ForEach(EditorTool.allCases) { tool in
                        Tile(selected: model.tool == tool, color: Brutal.yellow, help: "\(tool.title) (\(String(tool.key).uppercased()))", detail: tool.summary) {
                            model.tool = tool
                        } label: {
                            Image(systemName: tool.symbol).font(.system(size: 13, weight: .bold))
                        }
                    }
                }
                ToolGroup {
                    Tile(selected: model.showsImagePicker, color: Brutal.sky, help: "Add an image (⇧⌘I)", detail: "Place a recent capture or an image file beside your screenshot") {
                        model.showsImagePicker.toggle()
                    } label: {
                        Image(systemName: "photo.badge.plus").font(.system(size: 13, weight: .bold))
                    }
                    .popover(isPresented: $model.showsImagePicker, arrowEdge: .bottom) {
                        ImagePicker(excluding: model.fileURL) { urls in
                            model.showsImagePicker = false
                            model.addImageFiles(urls)
                        }
                    }
                    Tile(
                        selected: model.showsStylePopover, color: Brutal.sky, help: "Style",
                        detail: "Add a shadow, border or rounded corners to the selected image, a shadow or glow to a shape, arrow or text, or style the screenshot when nothing is selected",
                        isEnabled: model.styleTarget != nil
                    ) {
                        model.showsStylePopover.toggle()
                    } label: {
                        Image(systemName: "shadow").font(.system(size: 13, weight: .bold))
                    }
                    .popover(isPresented: $model.showsStylePopover, arrowEdge: .bottom) {
                        StylePopover(model: model)
                    }
                }
                Spacer(minLength: 0)
                ToolGroup {
                    Tile(selected: false, color: .white, help: "Undo (⌘Z)", isEnabled: model.undoStack.canUndo) {
                        model.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 13, weight: .bold))
                    }
                    Tile(selected: false, color: .white, help: "Redo (⇧⌘Z)", isEnabled: model.undoStack.canRedo) {
                        model.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward").font(.system(size: 13, weight: .bold))
                    }
                }
            }
            HStack(spacing: 14) {
                if model.showsStyle {
                    styleOptions
                } else if let redaction = model.paletteRedaction {
                    RedactionOptions(selected: redaction, amount: model.paletteRedactionAmount, choose: model.setRedaction, setAmount: model.setRedactionAmount, dragAmount: model.setDraggingStyle)
                } else if let spotlight = model.paletteSpotlight {
                    SpotlightOptions(
                        style: spotlight, chooseShape: model.setSpotlightShape, chooseLook: model.setSpotlightLook,
                        chooseSoftEdge: model.setSpotlightSoftEdge, dragSlider: model.setDraggingStyle
                    )
                } else {
                    Text(model.tool.summary)
                        .font(Brutal.caption)
                        .foregroundStyle(Brutal.ink.opacity(0.6))
                        .padding(.leading, 4)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 30 + Brutal.groupInset * 2)
        }
    }

    @ViewBuilder private var styleOptions: some View {
        if let shape = model.paletteShape {
            ShapeMenu(selected: shape, choose: model.setShape)
        }
        ToolGroup {
            ColorSwatches(
                selected: model.paletteColor,
                lastCustom: model.lastCustom(forFill: false),
                customHelp: "Custom colour",
                choose: { if let color = $0 { model.paletteColor = color } },
                pickCustom: { model.pickCustom($0, forFill: false) }
            )
        }
        if model.showsFill {
            ToolGroup {
                Text("FILL").font(Brutal.mono).foregroundStyle(Brutal.ink).padding(.horizontal, 4)
                ColorSwatches(
                    selected: model.paletteFill,
                    lastCustom: model.lastCustom(forFill: true),
                    allowsNone: true,
                    customHelp: "Custom fill colour",
                    choose: { model.paletteFill = $0 },
                    pickCustom: { model.pickCustom($0, forFill: true) }
                )
            }
        }
        WidthOptions(selected: model.lineWidthIndex, sizesText: model.sizesText) { model.lineWidthIndex = $0 }
        if let alignment = model.paletteAlignment {
            AlignmentOptions(selected: alignment, choose: model.setAlignment)
        }
    }
}

/// Line widths, or text sizes for text, notes and counters, whose width sets their size.
struct WidthOptions: View {
    /// What the three widths are called, here and for border widths in the Style popover.
    static let sizeNames = ["Small", "Medium", "Large"]

    let selected: Int
    let sizesText: Bool
    let choose: (Int) -> Void

    var body: some View {
        ToolGroup {
            ForEach(EditorStyle.widths.indices, id: \.self) { index in
                Tile(selected: selected == index, color: Brutal.sky, help: sizesText ? "Text size: \(Self.sizeNames[index])" : "Line width \(Int(EditorStyle.widths[index]))") {
                    choose(index)
                } label: {
                    if sizesText {
                        Text("A").font(.system(size: 9 + CGFloat(index) * 4, weight: .heavy))
                    } else {
                        Capsule().fill(Brutal.ink).frame(width: 16, height: EditorStyle.widths[index] + 1)
                    }
                }
            }
        }
    }
}

extension TextAlign {
    var textAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}

struct AlignmentOptions: View {
    let selected: TextAlign
    let choose: (TextAlign) -> Void

    var body: some View {
        ToolGroup {
            ForEach(TextAlign.allCases, id: \.self) { alignment in
                Tile(selected: selected == alignment, color: Brutal.sky, help: alignment.title) {
                    choose(alignment)
                } label: {
                    Image(systemName: alignment.symbol).font(.system(size: 13, weight: .bold))
                }
            }
        }
    }
}

struct ShapeOptions: View {
    let shapes: [BoxShape]
    let selected: BoxShape
    let choose: (BoxShape) -> Void

    var body: some View {
        ToolGroup {
            ForEach(shapes, id: \.self) { shape in
                Tile(selected: selected == shape, color: Brutal.sky, help: shape.title) {
                    choose(shape)
                } label: {
                    Image(systemName: shape.symbol).font(.system(size: 13, weight: .bold))
                }
            }
        }
    }
}

/// Every shape in one dropdown, which leaves room in the toolbar for the colour and fill beside it.
struct ShapeMenu: View {
    let selected: BoxShape
    let choose: (BoxShape) -> Void

    var body: some View {
        ToolGroup {
            BrutalDropdown(title: "Shape", entries: BoxShape.allCases.map { shape in
                .item(shape.title, symbol: shape.symbol, selected: shape == selected) { choose(shape) }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: selected.symbol).font(.system(size: 13, weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
                }
                .foregroundStyle(Brutal.ink)
                .frame(height: 30)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .brutalTip("Shape", detail: selected.title)
        }
    }
}

struct RedactionOptions: View {
    let selected: Redaction
    let amount: CGFloat
    let choose: (Redaction) -> Void
    let setAmount: (CGFloat) -> Void
    let dragAmount: (Bool) -> Void

    var body: some View {
        ToolGroup {
            ForEach(Redaction.allCases, id: \.self) { redaction in
                Tile(selected: selected == redaction, color: Brutal.sky, help: redaction.title) {
                    choose(redaction)
                } label: {
                    Image(systemName: redaction == .blur ? "drop.halffull" : "square.grid.3x3").font(.system(size: 13, weight: .bold))
                }
            }
        }
        ToolGroup {
            BrutalSlider(
                value: Binding(get: { amount }, set: { setAmount($0) }),
                range: Redaction.amounts.lowerBound...Redaction.amounts.upperBound,
                track: LinearGradient(colors: [.white, Brutal.sky], startPoint: .leading, endPoint: .trailing),
                width: 120,
                onEditingChanged: dragAmount
            )
            .frame(height: 30)
            .padding(.horizontal, 6)
            .accessibilityLabel(Text("Amount"))
            .brutalTip("Amount", detail: selected == .blur ? "How far the blur spreads." : "How big the blocks are.")
        }
    }
}

/// A spotlight's shape and edge, and the effect and strength every spotlight in the image shares.
struct SpotlightOptions: View {
    let style: SpotlightStyle
    let chooseShape: (BoxShape) -> Void
    let chooseLook: (SpotlightStyle.Effect, Double) -> Void
    let chooseSoftEdge: (Double) -> Void
    let dragSlider: (Bool) -> Void

    var body: some View {
        ShapeOptions(shapes: BoxShape.spotlightShapes, selected: style.shape, choose: chooseShape)
        ToolGroup {
            ForEach(SpotlightStyle.Effect.allCases, id: \.self) { effect in
                Tile(selected: style.effect == effect, color: Brutal.sky, help: "\(effect.title) outside", detail: "Applies to every spotlight in the image.") {
                    chooseLook(effect, style.strength)
                } label: {
                    Image(systemName: effect == .darken ? "moon.fill" : "drop.halffull").font(.system(size: 13, weight: .bold))
                }
            }
        }
        ToolGroup {
            BrutalSlider(
                value: Binding(get: { style.strength }, set: { chooseLook(style.effect, $0) }),
                range: SpotlightStyle.strengths,
                track: LinearGradient(colors: [Brutal.ink.opacity(SpotlightStyle.strengths.lowerBound), Brutal.ink.opacity(SpotlightStyle.strengths.upperBound)], startPoint: .leading, endPoint: .trailing),
                width: 120,
                onEditingChanged: dragSlider
            )
            .frame(height: 30)
            .padding(.horizontal, 6)
            .accessibilityLabel(Text("Strength"))
            .brutalTip("Strength", detail: "Applies to every spotlight in the image.")
        }
        ToolGroup {
            Text("EDGE").font(Brutal.mono).foregroundStyle(Brutal.ink).padding(.horizontal, 4)
            BrutalSlider(
                value: Binding(get: { style.softEdge }, set: { chooseSoftEdge($0) }),
                track: LinearGradient(colors: [.white, Brutal.sky], startPoint: .leading, endPoint: .trailing),
                width: 100,
                onEditingChanged: dragSlider
            )
            .frame(height: 30)
            .padding(.trailing, 6)
            .accessibilityLabel(Text("Soft edge"))
            .brutalTip("Soft edge", detail: "Fades the spotlight into the dim.")
        }
    }
}

extension RGBA {
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        self.init(c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    var swiftUIColor: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}
