import ShotCore
import SwiftUI

struct EditorRootView: View {
    @Bindable var model: EditorModel
    let canvas: EditorCanvasView

    var body: some View {
        VStack(spacing: Brutal.sectionGap) {
            HStack(spacing: 12) {
                Text(model.fileURL.lastPathComponent)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brutal.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.isDirty {
                    BrutalChip(text: "EDITED", color: Brutal.pink)
                }
                Spacer()
                ZoomMenu(model: model, canvas: canvas)
                CanvasMenu(model: model)
                Button("Copy") { model.copy() }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .brutalTip("Copy image (⌘C)")
                Button("Save") { model.save() }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow, compact: true))
                    .brutalTip("Save and copy (⌘S)")
            }
            .padding(.leading, GlassWindow.trafficLightsWidth)
            .frame(height: GlassWindow.titlebarHeight)
            .padding(.bottom, -Brutal.sectionGap / 2)
            EditorToolbar(model: model)
            CanvasHost(canvas: canvas)
                .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular))
                .glassCard()
        }
        .padding([.horizontal, .bottom], Brutal.windowInset)
    }
}

private struct CanvasHost: NSViewRepresentable {
    let canvas: EditorCanvasView

    func makeNSView(context: Context) -> EditorCanvasView { canvas }
    func updateNSView(_ nsView: EditorCanvasView, context: Context) {}
}

struct EditorToolbar: View {
    /// Matches `RGBA.presets`.
    static let colorNames = ["Red", "Orange", "Yellow", "Green", "Blue", "Black"]

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
                    RedactionOptions(selected: redaction, choose: model.setRedaction)
                } else if let spotlight = model.paletteSpotlight {
                    SpotlightOptions(style: spotlight, chooseShape: model.setSpotlightShape, chooseLook: model.setSpotlightLook)
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
    }
}

/// Line widths, or text sizes for text, notes and counters, whose width sets their size.
struct WidthOptions: View {
    private static let sizeNames = ["Small", "Medium", "Large"]

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

extension BoxShape {
    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .rounded: "app"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .diamond: "diamond"
        case .star: "star"
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
            Menu {
                ForEach(BoxShape.allCases, id: \.self) { shape in
                    Button { choose(shape) } label: { Label(shape.title, systemImage: shape.symbol) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selected.symbol).font(.system(size: 13, weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
                }
                .foregroundStyle(Brutal.ink)
                .frame(height: 30)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(Text("Shape: \(selected.title)"))
            .brutalTip("Shape", detail: selected.title)
        }
    }
}

struct RedactionOptions: View {
    let selected: Redaction
    let choose: (Redaction) -> Void

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
    }
}

/// A spotlight's shape, and the effect and strength every spotlight in the image shares.
struct SpotlightOptions: View {
    let style: SpotlightStyle
    let chooseShape: (BoxShape) -> Void
    let chooseLook: (SpotlightStyle.Effect, SpotlightStyle.Strength) -> Void

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
            ForEach(SpotlightStyle.Strength.allCases, id: \.self) { strength in
                Tile(selected: style.strength == strength, color: Brutal.sky, help: strength.title, detail: "Applies to every spotlight in the image.") {
                    chooseLook(style.effect, strength)
                } label: {
                    RoundedRectangle(cornerRadius: 3, style: .circular)
                        .fill(Brutal.ink.opacity(SpotlightStyle(strength: strength).dimAlpha))
                        .inkBorder(RoundedRectangle(cornerRadius: 3, style: .circular), width: 2)
                        .frame(width: 14, height: 14)
                }
            }
        }
    }
}

/// The preset colours and a rainbow swatch for a custom one. With `allowsNone`,
/// a first swatch clears the colour: `nil` is transparent, with nothing drawn.
struct ColorSwatches: View {
    let selected: RGBA?
    /// The custom colour picked last in this palette, which the rainbow swatch applies again.
    let lastCustom: RGBA?
    var allowsNone = false
    let customHelp: String
    let choose: (RGBA?) -> Void
    let pickCustom: (RGBA) -> Void

    var body: some View {
        if allowsNone {
            Swatch(color: nil, isSelected: selected == nil, name: "Transparent") { choose(nil) }
        }
        ForEach(RGBA.presets.indices, id: \.self) { index in
            Swatch(color: RGBA.presets[index], isSelected: selected == RGBA.presets[index], name: EditorToolbar.colorNames[index]) {
                choose(RGBA.presets[index])
            }
        }
        CustomColorButton(
            custom: selected.flatMap { RGBA.presets.contains($0) ? nil : $0 },
            lastCustom: lastCustom,
            fallback: selected ?? RGBA(1, 1, 1),
            help: customHelp,
            pick: pickCustom
        )
    }
}

/// A rainbow chip that applies the last custom colour and opens the colour editor on it in a popover,
/// so picking stays inside the app. While a custom colour is in use, it shows inside the rainbow ring.
private struct CustomColorButton: View {
    let custom: RGBA?
    let lastCustom: RGBA?
    /// What the colour editor starts on when no custom colour has been picked yet.
    let fallback: RGBA
    let help: String
    let pick: (RGBA) -> Void
    @State private var isOpen = false

    private var isSelected: Bool { isOpen || custom != nil }

    var body: some View {
        Button(action: open) {
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                if let custom {
                    Circle().fill(custom.swiftUIColor).inkBorder(Circle(), width: 2).padding(4)
                }
            }
            .inkBorder(Circle(), width: 2)
            .background(Circle().fill(Brutal.ink).offset(x: isSelected ? 2 : 0, y: isSelected ? 2 : 0))
            .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
            .frame(width: 26, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalTip(help)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(custom != nil ? .isSelected : [])
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ColorEditor(initial: lastCustom ?? fallback, pick: pick)
        }
    }

    private func open() {
        guard !isOpen else {
            isOpen = false
            return
        }
        if let lastCustom, lastCustom != custom {
            pick(lastCustom)
        }
        isOpen = true
    }
}

private struct ColorEditor: View {
    let pick: (RGBA) -> Void
    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    @State private var opacity: Double

    init(initial: RGBA, pick: @escaping (RGBA) -> Void) {
        self.pick = pick
        let c = NSColor(srgbRed: initial.r, green: initial.g, blue: initial.b, alpha: initial.a)
        _hue = State(initialValue: Double(c.hueComponent))
        _saturation = State(initialValue: Double(c.saturationComponent))
        _brightness = State(initialValue: Double(c.brightnessComponent))
        _opacity = State(initialValue: Double(initial.a))
    }

    private var color: Color { Color(hue: hue, saturation: saturation, brightness: brightness, opacity: opacity) }

    var body: some View {
        VStack(spacing: 12) {
            SaturationBrightnessField(hue: hue, saturation: $saturation, brightness: $brightness)
                .frame(width: 200, height: 140)
            GradientSlider(
                value: $hue,
                track: LinearGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing)
            )
            GradientSlider(
                value: $opacity,
                track: LinearGradient(colors: [color.opacity(0), color.opacity(1)], startPoint: .leading, endPoint: .trailing),
                checkerboard: true
            )
            Circle().fill(color).frame(width: 22, height: 22)
                .inkBorder(Circle(), width: 2)
        }
        .padding(16)
        .onChange(of: hue) { commit() }
        .onChange(of: saturation) { commit() }
        .onChange(of: brightness) { commit() }
        .onChange(of: opacity) { commit() }
    }

    private func commit() {
        pick(RGBA(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: opacity)))
    }
}

private struct SaturationBrightnessField: View {
    let hue: Double
    @Binding var saturation: Double
    @Binding var brightness: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color(hue: hue, saturation: 1, brightness: 1)
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .padding(1)
                    .inkBorder(Circle(), width: 1)
                    .position(x: saturation * size.width, y: (1 - brightness) * size.height)
            }
            .inkBorder(RoundedRectangle(cornerRadius: 6, style: .circular), width: 2)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                saturation = min(max(drag.location.x / size.width, 0), 1)
                brightness = 1 - min(max(drag.location.y / size.height, 0), 1)
            })
        }
    }
}

private struct GradientSlider: View {
    @Binding var value: Double
    let track: LinearGradient
    var checkerboard = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                if checkerboard {
                    Canvas { ctx, size in
                        let cell: CGFloat = 6
                        for x in 0...Int(size.width / cell) {
                            for y in 0...Int(size.height / cell) where (x + y) % 2 == 0 {
                                ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .color(.gray.opacity(0.4)))
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(Capsule().inset(by: 1))
                }
                Capsule().fill(track)
                    .inkBorder(Capsule(), width: 2)
                Circle().fill(.white)
                    .inkBorder(Circle(), width: 2)
                    .frame(width: 16, height: 16)
                    .offset(x: value * (width - 16))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(max((drag.location.x - 8) / (width - 16), 0), 1)
            })
        }
        .frame(width: 200, height: 16)
    }
}

private struct Swatch: View {
    let color: RGBA?
    let isSelected: Bool
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color?.swiftUIColor ?? .white)
                if color == nil {
                    Rectangle().fill(Brutal.red).frame(width: 2, height: 22).rotationEffect(.degrees(45))
                }
            }
            .inkBorder(Circle(), width: 2)
            .background(Circle().fill(Brutal.ink).offset(x: isSelected ? 2 : 0, y: isSelected ? 2 : 0))
            .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
            .frame(width: 26, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .brutalTip(name)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

extension RGBA {
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        self.init(c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    var swiftUIColor: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// Shows the zoom and offers the zoom commands; pinch and the keyboard shortcuts do the same.
private struct ZoomMenu: View {
    @Bindable var model: EditorModel
    let canvas: EditorCanvasView

    var body: some View {
        Menu {
            Button("Zoom In") { canvas.zoomIn() }
            Button("Zoom Out") { canvas.zoomOut() }
            Divider()
            Button("Zoom to Fit") { canvas.zoomToFit() }
            Button("Actual Size") { canvas.zoomToActualSize() }
        } label: {
            HStack(spacing: 6) {
                Text("\(Int((model.zoom * 100).rounded()))%")
                    .monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(BrutalButtonStyle(compact: true))
        .fixedSize()
        .brutalTip("Zoom in (⌘+), out (⌘-), to fit (⌘0) or to actual size (⌘1). Pinch to zoom; scroll or Space-drag to move around.")
    }
}

private struct CanvasMenu: View {
    private static let white = RGBA(1, 1, 1)

    @Bindable var model: EditorModel

    var body: some View {
        Menu {
            Button("Fit to Content") { model.fitToContent() }
            Button("Trim to Image") { model.trimToImage() }
                .disabled(!model.document.hasPadding)
            Divider()
            Picker("Background", selection: Binding(get: { model.document.background }, set: { model.setBackground($0) })) {
                // JPEG has no alpha, so it can't keep transparent padding.
                if !model.isJPEG {
                    Text("Transparent").tag(RGBA?.none)
                }
                Text("White").tag(RGBA?.some(Self.white))
                ForEach(RGBA.presets.indices, id: \.self) { index in
                    Text(EditorToolbar.colorNames[index]).tag(RGBA?.some(RGBA.presets[index]))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Canvas")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(BrutalButtonStyle(compact: true))
        .fixedSize()
        .brutalTip("Canvas size and background")
    }
}

struct ToolGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(Brutal.groupInset)
        .brutalSurface(Color.white.opacity(0.5), glass: true, radius: 10, shadow: 3)
    }
}

struct Tile<Label: View>: View {
    let selected: Bool
    let color: Color
    let help: String
    /// What the tile does, shown under `help` in its tip.
    var detail: String?
    /// A disabled tile is dimmed but still shows its tip.
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(Brutal.ink)
                .frame(width: 30, height: 30)
                .background {
                    if selected {
                        Color.clear.brutalSurface(color, radius: 7, shadow: 2)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 7, style: .circular).fill(Brutal.ink.opacity(0.08))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
        .brutalTip(help, detail: detail)
    }
}
