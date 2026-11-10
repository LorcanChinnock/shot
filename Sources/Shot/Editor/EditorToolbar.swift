import ShotCore
import SwiftUI

/// The title bar's one group of tools, from Edit › Image editor · annotate: the eleven drawing tools, a divider, then
/// Add image and Crop. The selected tool is the ink button; the hand tool has no button of its own.
struct EditorToolGroup: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 1) {
            ForEach(EditorToolbarLayout.drawingTools) { toolTile($0) }
            Rectangle()
                .fill(Brutal.controlEdge)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 4)
                .accessibilityHidden(true)
            Tile(selected: model.showsImagePicker, help: "Add an image", key: "⇧⌘I", detail: "Place a recent capture or an image file beside your screenshot") {
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
            ForEach(EditorToolbarLayout.afterDivider) { toolTile($0) }
        }
        .padding(3)
        .background(Brutal.fieldFill, in: RoundedRectangle(cornerRadius: Brutal.Radius.group, style: .circular))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools"))
    }

    private func toolTile(_ tool: EditorTool) -> some View {
        Tile(selected: EditorToolbarLayout.selectedButton(for: model.tool) == tool, tool: true, help: tool.title, key: String(tool.key).uppercased(), detail: tool.summary) {
            model.tool = tool
        } label: {
            Image(systemName: tool.symbol).font(Brutal.toolIcon)
        }
    }
}

/// The names of `RGBA.presets`, for swatches. Not `RGBA.presetNames`, which agents read and so stays English.
enum PresetColorNames {
    static let all = [
        String(localized: "Red"), String(localized: "Orange"), String(localized: "Yellow"), String(localized: "Green"),
        String(localized: "Blue"), String(localized: "Black"), String(localized: "White"),
    ]
}

/// The names of the three widths, for text sizes in the style bar and border widths in the style sections.
enum WidthOptions {
    static let sizeNames = [String(localized: "Small"), String(localized: "Medium"), String(localized: "Large")]
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
                Tile(selected: selected == aspect, help: aspect.title, detail: aspect.detail) {
                    choose(aspect)
                } label: {
                    Text(aspect.label).font(.scaled(9, weight: .heavy)).minimumScaleFactor(0.7).lineLimit(1)
                }
            }
        }
        Button("Reset", action: reset)
            .buttonStyle(BrutalButtonStyle(.plain))
            .disabled(!canReset)
            .brutalTip("Reset", detail: "Takes the crop off, so the whole image is kept.")
    }
}

extension CropAspect {
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

extension RGBA {
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        self.init(c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    var swiftUIColor: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}
