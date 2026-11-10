import AppKit
import ShotCore
import SwiftUI

/// The drawing options while a tool is picked: the image editor's style bar, from Edit › Image editor · annotate, centred
/// 12 pt down from the top of the video's well. The colours and widths are in the bar, and the shape, fill, white and custom
/// colours, alignment, a blur's amount and a spotlight's strength under More style. The select tool with nothing selected
/// shows no bar, and neither does crop mode. The tools themselves are in `DrawToolColumn`, beside the video.
struct VideoStyleBar: View {
    @Bindable var model: VideoEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var content: StyleBarContent? {
        guard let tool = model.annotationTool, !model.isCropping else {
            return nil
        }
        return StyleBarContent.content(
            showsStyle: model.showsStyle, tool: tool, showsRedaction: model.paletteRedaction != nil, showsSpotlight: model.paletteSpotlight != nil
        )
    }

    var body: some View {
        ZStack {
            if let content {
                StyleBar(model: model, content: content)
                    .fixedSize()
                    .padding(.top, StyleBarPlacement.inset)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        // Arriving is the panel moment, as in the image editor; changing what it shows is instant.
        .animation(Motion.animation(.panelArrive, reduceMotion: reduceMotion), value: content)
        .onChange(of: content) {
            if content == nil {
                model.showsMoreStyle = false
            }
        }
    }
}

/// The drawing tools in a floating column over the left of the video while Draw is on, from Edit › Video editor and
/// export: the drawing tools and Add image, a divider, then Crop video. The selected tool is the ink button. In a window
/// too short for all of them, the column scrolls.
struct DrawToolColumn: View {
    @Bindable var model: VideoEditorModel
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ViewThatFits(in: .vertical) {
            panel { buttons }
            panel {
                ScrollView(.vertical, showsIndicators: false) { buttons }
            }
        }
        .padding(.vertical, columnInset)
    }

    private var buttons: some View {
        VStack(spacing: 2) {
            ForEach(VideoDrawTools.drawing, id: \.self) { tile($0) }
            Rectangle()
                .fill(Brutal.controlEdge)
                .frame(width: 18, height: 1)
                .padding(.vertical, 3)
                .accessibilityHidden(true)
            ForEach(VideoDrawTools.afterDivider, id: \.self) { tile($0) }
        }
    }

    private func panel(@ViewBuilder _ content: () -> some View) -> some View {
        let shape = RoundedRectangle(cornerRadius: Brutal.Radius.group, style: .circular)
        return content()
            .padding(4)
            .fixedSize(horizontal: true, vertical: false)
            .depth(.float, fill: solid ? AnyShapeStyle(Brutal.group) : AnyShapeStyle(columnFill), radius: Brutal.Radius.group)
            .overlay {
                if contrast == .increased {
                    Color.clear.inkBorder(shape, width: 1, color: Brutal.ink.opacity(0.6))
                }
            }
            .contentShape(shape)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Draw tools"))
    }

    private func tile(_ button: VideoDrawTools.Button) -> some View {
        let selected = VideoDrawTools.selected(tool: model.annotationTool, cropping: model.isCropping) == button
        let key = VideoDrawTools.key(for: button)
        return Group {
            switch button {
            case let .tool(tool):
                Tile(selected: selected, tool: true, help: tool.title, key: key, detail: tool.summary) {
                    model.pickDrawTool(tool)
                } label: {
                    icon(tool.symbol)
                }
            case .addImage:
                Tile(selected: false, tool: true, help: "Add an image", key: key, detail: "Shows a picture over the video, such as a logo.") {
                    pickImage()
                } label: {
                    icon("photo.badge.plus")
                }
            case .cropVideo:
                Tile(selected: selected, tool: true, help: "Crop video", key: key, detail: "Crops the selected clip's picture, or the whole frame when nothing is selected.") {
                    if model.isCropping {
                        model.cancelCrop()
                    } else {
                        model.cropFromDrawTools()
                    }
                } label: {
                    icon("crop")
                }
            }
        }
    }

    /// The board's 32 × 30 buttons: the tile's padding around an 18 × 20 label.
    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(Brutal.toolIcon)
            .frame(minWidth: 18, minHeight: 20)
    }

    private var solid: Bool { contrast == .increased || reduceTransparency }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = String(localized: "Choose an image to show over the video")
        if panel.runModal() == .OK, let url = panel.url {
            model.addImage(from: url)
        }
    }
}

/// Clear of the video's top and bottom edges, so a short window scrolls the column rather than touching them.
private let columnInset: CGFloat = 12

/// The board's fill, a touch see-through over the video.
private let columnFill = Color(light: .white.opacity(0.97), dark: Color(hex: 0x2C2C30).opacity(0.92))

extension VideoEditorModel: StyleBarEditing {}
