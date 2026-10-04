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
            ToolGroup {
                ForEach(RGBA.presets.indices, id: \.self) { index in
                    let rgba = RGBA.presets[index]
                    let selected = model.paletteIndex == index
                    Button {
                        model.paletteIndex = index
                    } label: {
                        Circle()
                            .fill(Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b))
                            .overlay(Circle().strokeBorder(Brutal.ink, lineWidth: 2))
                            .background(Circle().fill(Brutal.ink).offset(x: selected ? 2 : 0, y: selected ? 2 : 0))
                            .frame(width: selected ? 22 : 18, height: selected ? 22 : 18)
                            .frame(width: 26, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Self.colorNames[index])
                    .accessibilityLabel(Text(Self.colorNames[index]))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: selected)
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
