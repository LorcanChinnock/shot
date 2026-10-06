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
                RedactMenu(model: model)
                CanvasMenu(model: model)
                Button("Copy") { model.copy() }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .help("Copy image (⌘C)")
                Button("Save") { model.save() }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow, compact: true))
                    .help("Save and copy (⌘S)")
            }
            .padding(.leading, GlassWindow.trafficLightsWidth)
            .frame(height: GlassWindow.titlebarHeight)
            .padding(.bottom, -Brutal.sectionGap / 2)
            EditorToolbar(model: model)
            CanvasHost(canvas: canvas)
                .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .continuous))
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
                        Tile(selected: model.tool == tool, color: Brutal.yellow, help: "\(tool.title) (\(String(tool.key).uppercased()))") {
                            model.tool = tool
                        } label: {
                            Image(systemName: tool.symbol).font(.system(size: 13, weight: .bold))
                        }
                    }
                }
                Spacer(minLength: 0)
                ToolGroup {
                    Tile(selected: false, color: .white, help: "Undo (⌘Z)") {
                        model.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 13, weight: .bold))
                    }
                    .disabled(!model.undoStack.canUndo)
                    .opacity(model.undoStack.canUndo ? 1 : 0.35)
                    Tile(selected: false, color: .white, help: "Redo (⇧⌘Z)") {
                        model.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward").font(.system(size: 13, weight: .bold))
                    }
                    .disabled(!model.undoStack.canRedo)
                    .opacity(model.undoStack.canRedo ? 1 : 0.35)
                }
            }
            HStack(spacing: 14) {
                ToolGroup {
                    ColorSwatches(
                        selected: model.paletteColor,
                        recents: model.recentColors,
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
                            recents: model.recentColors,
                            allowsNone: true,
                            customHelp: "Custom fill colour",
                            choose: { model.paletteFill = $0 },
                            pickCustom: { model.pickCustom($0, forFill: true) }
                        )
                    }
                }
                ToolGroup {
                    ForEach(EditorModel.baseWidths.indices, id: \.self) { index in
                        Tile(selected: model.lineWidthIndex == index, color: Brutal.sky, help: "Line width \(Int(EditorModel.baseWidths[index]))") {
                            model.lineWidthIndex = index
                        } label: {
                            Capsule().fill(Brutal.ink).frame(width: 16, height: EditorModel.baseWidths[index] + 1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// The preset colours, the custom ones picked lately, and a colour well for a new one. With `allowsNone`,
/// a first swatch clears the colour: `nil` is transparent, with nothing drawn.
private struct ColorSwatches: View {
    let selected: RGBA?
    let recents: [RGBA]
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
        ForEach(recents, id: \.self) { recent in
            Swatch(color: recent, isSelected: selected == recent, name: "Recent colour") { choose(recent) }
        }
        ColorPicker("", selection: Binding(
            get: { (selected ?? RGBA(1, 1, 1)).swiftUIColor },
            set: { pickCustom(RGBA(NSColor($0))) }
        ), supportsOpacity: true)
            .labelsHidden()
            .frame(width: 34, height: 30)
            .help(customHelp)
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
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Brutal.ink, lineWidth: 2))
            .background(Circle().fill(Brutal.ink).offset(x: isSelected ? 2 : 0, y: isSelected ? 2 : 0))
            .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
            .frame(width: 26, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
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
        .help("Zoom in (⌘+), out (⌘-), to fit (⌘0) or to actual size (⌘1). Pinch to zoom; scroll or Space-drag to move around.")
    }
}

/// Auto-redact: finds sensitive text and covers each piece with a blur or pixelate region.
private struct RedactMenu: View {
    @Bindable var model: EditorModel

    var body: some View {
        Menu {
            Button("Blur Sensitive Text") { model.autoRedact(.blur) }
            Button("Pixelate Sensitive Text") { model.autoRedact(.pixelate) }
        } label: {
            HStack(spacing: 6) {
                Text(model.isRedacting ? "Redacting…" : "Redact")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(BrutalButtonStyle(compact: true))
        .fixedSize()
        .disabled(model.isRedacting)
        .help("Hide emails, phone numbers, card numbers and IP addresses")
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
        .help("Canvas size and background")
    }
}

private struct ToolGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(Brutal.groupInset)
        .brutalSurface(Color.white.opacity(0.5), glass: true, radius: 10, shadow: 3)
    }
}

private struct Tile<Label: View>: View {
    let selected: Bool
    let color: Color
    let help: String
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
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Brutal.ink.opacity(0.08))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}
