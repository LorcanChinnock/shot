import ShotCore
import SwiftUI

struct EditorToolbar: View {
    /// Matches `RGBA.presets`. Not `RGBA.presetNames`, which agents read and so stays English.
    static let colorNames = [
        String(localized: "Red"), String(localized: "Orange"), String(localized: "Yellow"), String(localized: "Green"),
        String(localized: "Blue"), String(localized: "Black"), String(localized: "White"),
    ]

    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ToolGroup {
                    ForEach(EditorTool.allCases) { tool in
                        Tile(selected: model.tool == tool, color: Brutal.yellow, help: "\(tool.title) (\(String(tool.key).uppercased()))", detail: tool.summary) {
                            model.tool = tool
                        } label: {
                            Image(systemName: tool.symbol).font(Brutal.toolIcon)
                        }
                    }
                }
                ToolGroup {
                    Tile(selected: model.showsImagePicker, color: Brutal.sky, help: "Add an image (⇧⌘I)", detail: "Place a recent capture or an image file beside your screenshot") {
                        model.showsImagePicker.toggle()
                    } label: {
                        Image(systemName: "photo.badge.plus").font(Brutal.toolIcon)
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
                        Image(systemName: "paintpalette").font(Brutal.toolIcon)
                    }
                    .popover(isPresented: $model.showsStylePopover, arrowEdge: .bottom) {
                        StylePopover(model: model)
                    }
                }
                Spacer(minLength: 0)
                ToolGroup {
                    Tile(selected: false, color: Brutal.paper, help: "Undo (⌘Z)", isEnabled: model.undoStack.canUndo) {
                        model.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward").font(Brutal.toolIcon)
                    }
                    Tile(selected: false, color: Brutal.paper, help: "Redo (⇧⌘Z)", isEnabled: model.undoStack.canRedo) {
                        model.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward").font(Brutal.toolIcon)
                    }
                }
            }
            HStack(spacing: 14) {
                if model.showsStyle {
                    styleOptions
                    resetButton
                } else if model.tool == .crop {
                    CropOptions(selected: model.cropAspect, canReset: model.canResetCrop, choose: model.chooseCropAspect, reset: model.resetCrop)
                } else if let redaction = model.paletteRedaction {
                    RedactionOptions(selected: redaction, amount: model.paletteRedactionAmount, choose: model.setRedaction, setAmount: model.setRedactionAmount, dragAmount: model.setDraggingStyle)
                    resetButton
                } else if let spotlight = model.paletteSpotlight {
                    SpotlightOptions(
                        style: spotlight, chooseShape: model.setSpotlightShape, chooseLook: model.setSpotlightLook,
                        chooseSoftEdge: model.setSpotlightSoftEdge, dragSlider: model.setDraggingStyle
                    )
                    resetButton
                } else {
                    Text(model.tool.summary)
                        .font(Brutal.caption)
                        .foregroundStyle(Brutal.faded(0.6))
                        .padding(.leading, 4)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 30 + Brutal.groupInset * 2)
        }
    }

    /// Puts this tool's options back to how a fresh install starts, so the next arrow, blur or spotlight comes out plain too.
    private var resetButton: some View {
        Button("Reset", action: model.resetToolOptions)
            .buttonStyle(BrutalButtonStyle(compact: true))
            .disabled(!model.canResetToolOptions)
            .brutalTip("Reset", detail: "Puts this tool's colour, size and other options back to how a new install starts. Your saved custom colours stay.")
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
                pickCustom: { model.pickCustom($0, forFill: false) },
                beginPicking: model.beginColorPick
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
                    pickCustom: { model.pickCustom($0, forFill: true) },
                    beginPicking: model.beginColorPick
                )
            }
        }
        WidthOptions(selected: model.lineWidthIndex, sizesText: model.sizesText) { model.lineWidthIndex = $0 }
        if let alignment = model.paletteAlignment {
            AlignmentOptions(selected: alignment, choose: model.setAlignment)
        }
        if let verticalAlignment = model.paletteVerticalAlignment {
            VerticalAlignmentOptions(selected: verticalAlignment, choose: model.setVerticalAlignment)
        }
    }
}

/// Line widths, or text sizes for text, notes and counters, whose width sets their size.
struct WidthOptions: View {
    /// What the three widths are called, here and for border widths in the Style popover.
    static let sizeNames = [String(localized: "Small"), String(localized: "Medium"), String(localized: "Large")]

    let selected: Int
    let sizesText: Bool
    let choose: (Int) -> Void

    var body: some View {
        ToolGroup {
            ForEach(EditorStyle.widths.indices, id: \.self) { index in
                Tile(selected: selected == index, color: Brutal.sky, help: sizesText ? "Text size: \(Self.sizeNames[index])" : "Line width: \(Int(EditorStyle.widths[index]))") {
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
                    Image(systemName: alignment.symbol).font(Brutal.toolIcon)
                }
            }
        }
    }
}

struct VerticalAlignmentOptions: View {
    let selected: VerticalTextAlign
    let choose: (VerticalTextAlign) -> Void

    var body: some View {
        ToolGroup {
            ForEach(VerticalTextAlign.allCases, id: \.self) { alignment in
                Tile(selected: selected == alignment, color: Brutal.sky, help: alignment.title) {
                    choose(alignment)
                } label: {
                    Image(systemName: alignment.symbol).font(Brutal.toolIcon)
                }
            }
        }
    }
}

/// What the crop tool offers: the shape to hold the crop to, and taking the crop off.
struct CropOptions: View {
    let selected: CropAspect
    let canReset: Bool
    let choose: (CropAspect) -> Void
    let reset: () -> Void

    var body: some View {
        ToolGroup {
            Text("ASPECT").font(Brutal.mono).foregroundStyle(Brutal.ink).padding(.horizontal, 4)
            ForEach(CropAspect.allCases, id: \.self) { aspect in
                Tile(selected: selected == aspect, color: Brutal.sky, help: aspect.title, detail: aspect.detail) {
                    choose(aspect)
                } label: {
                    Text(aspect.label).font(.scaled(9, weight: .heavy)).minimumScaleFactor(0.7).lineLimit(1)
                }
            }
        }
        Button("Reset", action: reset)
            .buttonStyle(BrutalButtonStyle(compact: true))
            .disabled(!canReset)
            .brutalTip("Reset", detail: "Takes the crop off, so the whole image is kept.")
    }
}

private extension CropAspect {
    /// What the tile shows. Ratios aren't translated.
    var label: String {
        switch self {
        case .free: String(localized: "Free")
        case .square: "1:1"
        case .fourThree: "4:3"
        case .sixteenNine: "16:9"
        }
    }

    var title: String {
        switch self {
        case .free: String(localized: "Free crop")
        case .square: String(localized: "Square, 1:1")
        case .fourThree: "4:3"
        case .sixteenNine: "16:9"
        }
    }

    var detail: String {
        switch self {
        case .free: String(localized: "Drag the crop to any shape.")
        default: String(localized: "Keeps the crop this shape, wide or tall to match it.")
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
                    Image(systemName: shape.symbol).font(Brutal.toolIcon)
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
                    Image(systemName: selected.symbol).font(Brutal.toolIcon)
                    Image(systemName: "chevron.down").font(.scaled(9, weight: .black))
                }
                .foregroundStyle(Brutal.ink)
                .frame(height: 30)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .brutalTip(String(localized: "Shape"), detail: selected.title)
        }
    }
}

struct RedactionOptions: View {
    let selected: Redaction
    let amount: CGFloat
    let choose: (Redaction) -> Void
    let setAmount: (CGFloat) -> Void

    // A switch, since string extraction misses the second branch of a ternary passed as an optional.
    private var amountDetail: LocalizedStringResource {
        switch selected {
        case .blur: "How far the blur spreads."
        case .pixelate: "How big the blocks are."
        }
    }
    let dragAmount: (Bool) -> Void

    var body: some View {
        ToolGroup {
            ForEach(Redaction.allCases, id: \.self) { redaction in
                Tile(selected: selected == redaction, color: Brutal.sky, help: redaction.title) {
                    choose(redaction)
                } label: {
                    Image(systemName: redaction == .blur ? "drop.halffull" : "square.grid.3x3").font(Brutal.toolIcon)
                }
            }
        }
        ToolGroup {
            BrutalSlider(
                value: Binding(get: { amount }, set: { setAmount($0) }),
                range: Redaction.amounts.lowerBound...Redaction.amounts.upperBound,
                track: LinearGradient(colors: [Brutal.paper, Brutal.sky], startPoint: .leading, endPoint: .trailing),
                width: 120,
                onEditingChanged: dragAmount
            )
            .frame(height: 30)
            .padding(.horizontal, 6)
            .accessibilityLabel(Text("Amount"))
            .brutalTip("Amount", detail: amountDetail)
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
                    Image(systemName: effect == .darken ? "moon.fill" : "drop.halffull").font(Brutal.toolIcon)
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
                track: LinearGradient(colors: [Brutal.paper, Brutal.sky], startPoint: .leading, endPoint: .trailing),
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
