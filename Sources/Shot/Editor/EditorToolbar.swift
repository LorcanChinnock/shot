import ShotCore
import SwiftUI

struct EditorToolbar: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 26, height: 24)
                        .background(model.tool == tool ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("\(tool.title) (\(String(tool.key).uppercased()))")
            }
            Divider().frame(height: 20).padding(.horizontal, 6)
            ForEach(RGBA.presets.indices, id: \.self) { index in
                let rgba = RGBA.presets[index]
                Button {
                    model.colorIndex = index
                } label: {
                    Circle()
                        .fill(Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary, lineWidth: model.colorIndex == index ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
            }
            Divider().frame(height: 20).padding(.horizontal, 6)
            ForEach(EditorModel.baseWidths.indices, id: \.self) { index in
                Button {
                    model.widthIndex = index
                } label: {
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 18, height: EditorModel.baseWidths[index])
                        .frame(width: 26, height: 24)
                        .background(model.widthIndex == index ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.undoStack.canUndo)
                .help("Undo (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.undoStack.canRedo)
                .help("Redo (⇧⌘Z)")
            Button("Copy") { model.copy() }.fixedSize()
                .help("Copy (⌘C)")
            Button("Save") { model.save() }.fixedSize()
                .help("Save and copy (⌘S)")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }
}
