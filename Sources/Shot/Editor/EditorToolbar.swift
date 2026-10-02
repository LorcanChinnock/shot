import ShotCore
import SwiftUI

struct EditorRootView: View {
    @Bindable var model: EditorModel
    let canvas: EditorCanvasView

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(model.fileURL.lastPathComponent)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brutal.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.isDirty {
                    BrutalChip(text: "EDITED", color: Brutal.pink)
                }
                Spacer()
                Button("Copy") { model.copy() }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .help("Copy image (⌘C)")
                Button("Save") { model.save() }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow, compact: true))
                    .help("Save and copy (⌘S)")
            }
            .padding(.leading, GlassWindow.trafficLightsWidth)
            .frame(height: 28)
            EditorToolbar(model: model)
            CanvasHost(canvas: canvas)
                .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .continuous))
                .glassCard()
        }
        .padding(.top, 1)
        .padding([.horizontal, .bottom], 16)
    }
}

private struct CanvasHost: NSViewRepresentable {
    let canvas: EditorCanvasView

    func makeNSView(context: Context) -> EditorCanvasView { canvas }
    func updateNSView(_ nsView: EditorCanvasView, context: Context) {}
}

struct EditorToolbar: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
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
                    let selected = model.colorIndex == index
                    Button {
                        model.colorIndex = index
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
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: selected)
                }
            }
            ToolGroup {
                ForEach(EditorModel.baseWidths.indices, id: \.self) { index in
                    Tile(selected: model.widthIndex == index, color: Brutal.sky, help: "Line width \(Int(EditorModel.baseWidths[index]))") {
                        model.widthIndex = index
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

private struct ToolGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 3) {
            content
        }
        .padding(4)
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
        .onHover { hovering = $0 }
    }
}
