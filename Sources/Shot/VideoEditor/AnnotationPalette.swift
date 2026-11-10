import AppKit
import ShotCore
import SwiftUI

/// The drawing options under the video while a tool is picked: colours, fill and width, the shape, blur or spotlight
/// options, or what the tool does. The tools themselves are in `DrawToolColumn`, beside the video.
struct AnnotationPalette: View {
    /// One row of tool groups.
    static let height: CGFloat = 30 + Brutal.groupInset * 2

    @Bindable var model: VideoEditorModel

    var body: some View {
        HStack(spacing: 14) {
            if model.showsStyle {
                styleOptions
            } else if let redaction = model.paletteRedaction {
                RedactionOptions(selected: redaction, amount: model.paletteRedactionAmount, choose: model.setRedaction, setAmount: model.setRedactionAmount) { dragging in
                    dragging ? model.beginDrag() : model.endDrag()
                }
            } else if let spotlight = model.paletteSpotlight {
                SpotlightOptions(
                    style: spotlight, chooseShape: model.setSpotlightShape, chooseLook: model.setSpotlightLook, chooseSoftEdge: model.setSpotlightSoftEdge
                ) { dragging in
                    dragging ? model.beginDrag() : model.endDrag()
                }
            } else if let tool = model.annotationTool {
                Text(tool.summary)
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.faded(0.6))
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.height)
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
