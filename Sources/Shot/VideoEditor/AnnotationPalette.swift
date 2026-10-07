import AppKit
import ShotCore
import SwiftUI

/// Tools, colours and widths for drawing over the video, laid out like the image editor's toolbar.
struct AnnotationPalette: View {
    /// Two rows of tool groups and the gap between them.
    static let height: CGFloat = 2 * (30 + Brutal.groupInset * 2) + 12

    @Bindable var model: VideoEditorModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ToolGroup {
                    ForEach(EditorTool.allCases.filter { $0 != .crop }) { tool in
                        Tile(selected: model.annotationTool == tool, color: Brutal.yellow, help: tool.title, detail: tool.summary) {
                            model.annotationStyle.tool = tool
                            model.setAnnotationTool(tool)
                        } label: {
                            Image(systemName: tool.symbol).font(.system(size: 13, weight: .bold))
                        }
                    }
                    Tile(selected: false, color: Brutal.yellow, help: "Add an image") {
                        pickImage()
                    } label: {
                        Image(systemName: "photo").font(.system(size: 13, weight: .bold))
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                if model.showsStyle {
                    styleOptions
                } else if let tool = model.annotationTool {
                    Text(tool.summary)
                        .font(Brutal.caption)
                        .foregroundStyle(Brutal.ink.opacity(0.6))
                        .padding(.leading, 4)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 30 + Brutal.groupInset * 2)
        }
        .frame(height: Self.height)
    }

    @ViewBuilder private var styleOptions: some View {
        ToolGroup {
            ColorSwatches(
                selected: model.paletteColor,
                recents: model.annotationStyle.recentColors,
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
                    recents: model.annotationStyle.recentColors,
                    allowsNone: true,
                    customHelp: "Custom fill colour",
                    choose: { model.paletteFill = $0 },
                    pickCustom: { model.pickCustom($0, forFill: true) }
                )
            }
        }
        ToolGroup {
            ForEach(EditorStyle.widths.indices, id: \.self) { index in
                Tile(selected: model.lineWidthIndex == index, color: Brutal.sky, help: "Line width \(Int(EditorStyle.widths[index]))") {
                    model.lineWidthIndex = index
                } label: {
                    Capsule().fill(Brutal.ink).frame(width: 16, height: EditorStyle.widths[index] + 1)
                }
            }
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image to show over the video"
        if panel.runModal() == .OK, let url = panel.url {
            model.addImage(from: url)
        }
    }
}
