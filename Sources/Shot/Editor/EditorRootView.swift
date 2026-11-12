import ShotCore
import SwiftUI

struct EditorRootView: View {
    @Bindable var model: EditorModel
    let canvas: EditorCanvasView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // From Edit › Image editor: the title bar over a hairline, then the canvas edge to edge, with a side panel flush
        // against its right.
        VStack(spacing: 0) {
            EditorTitleBar(model: model)
                .padding(.leading, GlassWindow.trafficLightsWidth)
                .padding(.trailing, 12)
                .frame(height: GlassWindow.titlebarHeight)
            Rectangle()
                .fill(ContrastAware(standard: Theme.hairline, increased: Theme.ink.opacity(0.6)))
                .frame(height: 1)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                CanvasHost(canvas: canvas)
                    // The canvas's scroll view draws past its bounds, over the title bar, unless it's clipped.
                    .clipped()
                    .overlay(alignment: .bottom) { CanvasFoot(model: model, canvas: canvas) }
                    .overlay { StyleBarOverlay(model: model) }
                    .overlay { CropBarOverlay(model: model) }
                if model.showsStylePanel {
                    StylePanel(model: model)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
                if model.showsLayers {
                    LayersPanel(
                        rows: model.layerRows,
                        frame: model.frameRow,
                        selection: Binding(get: { model.selectedIDs }, set: { model.selectLayers($0) }),
                        onMove: model.moveLayers,
                        onHide: { model.setHidden($1, $0) },
                        onLock: { model.setLocked($1, $0) },
                        onRename: model.renameLayer,
                        onDuplicate: model.duplicateLayers,
                        onDelete: model.deleteLayers,
                        onCropImage: { id in
                            model.cropImage(id)
                            // As from the Frame row: Return and Esc go to the crop, not the layer list.
                            canvas.window?.makeFirstResponder(canvas)
                        },
                        onResetImageCrop: model.resetImageCrop,
                        onSelectFrame: {
                            model.tool = .crop
                            // Return and Esc go to the canvas, not the panel that was clicked.
                            canvas.window?.makeFirstResponder(canvas)
                        },
                        onHideFrame: model.setFrameCropHidden,
                        onDeleteFrame: model.deleteFrame,
                        onTool: { tool in
                            model.tool = tool
                            if tool == .crop {
                                // As from the Frame row: Return and Esc go to the crop, not the layer list.
                                canvas.window?.makeFirstResponder(canvas)
                            }
                        }
                    )
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(Motion.animation(.panelArrive, reduceMotion: reduceMotion), value: model.showsStylePanel)
        .animation(Motion.animation(.panelArrive, reduceMotion: reduceMotion), value: model.showsLayers)
    }
}

/// The title bar and toolbar in one, from Edit › Image editor · annotate: the file beside the traffic lights, the tools in
/// the middle, then Undo, the Canvas menu, Style, Layers, Share, Save and Copy, the one main button.
private struct EditorTitleBar: View {
    @Bindable var model: EditorModel

    var body: some View {
        // The Canvas menu is the board's "Canvas ⌄" while the window has room for it beside a 100 pt file name, and a
        // tile with the same menu when it doesn't, such as at the 1,060 pt minimum width.
        ViewThatFits(in: .horizontal) {
            row(compactCanvas: false)
            row(compactCanvas: true)
        }
    }

    private func row(compactCanvas: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.fileURL.lastPathComponent)
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                    .truncationMode(.middle)
                subtitle
                    .font(Theme.caption)
                    .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                    .monospacedDigit()
            }
            .lineLimit(1)
            // Measured at its 100 pt floor when choosing the Canvas menu's form, and as wide as the room allows after.
            .frame(minWidth: 100, idealWidth: 100, maxWidth: 190, alignment: .leading)
            .padding(.leading, 8)
            // The name takes its room first; the tools sit centred in what's left.
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            EditorToolGroup(model: model)
            Spacer(minLength: 0)
            actions(compactCanvas: compactCanvas)
        }
    }

    private var size: String { EditorToolbarLayout.sizeLabel(model.document.exportSize) }

    private var subtitle: Text {
        model.isDirty ? Text("Edited · \(size)") : Text(verbatim: size)
    }

    private func actions(compactCanvas: Bool) -> some View {
        HStack(spacing: 4) {
            Tile(selected: false, help: "Undo", key: "⌘Z", detail: "Redo with ⇧⌘Z.", isEnabled: model.history.canUndo) {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward").font(Theme.toolIcon)
            }
            CanvasMenu(model: model, compact: compactCanvas)
            Tile(
                selected: model.showsStylePanel, help: "Style",
                detail: "Shows a panel beside the canvas for the screenshot's background, padding, size, shadow and corners, or the selected image's, shape's or text's shadow and border."
            ) {
                model.toggleStylePanel()
            } label: {
                Image(systemName: "paintpalette").font(Theme.toolIcon)
            }
            Tile(selected: model.showsLayers, help: "Layers", key: "⌘L", detail: "Shows every mark and image in a list beside the canvas.") {
                model.toggleLayers()
            } label: {
                Image(systemName: "sidebar.right").font(Theme.toolIcon)
            }
            Rectangle()
                .fill(Theme.controlEdge)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 6)
                .accessibilityHidden(true)
            ShareMenu(model: model)
            Button("Save") { Task { await model.save() } }
                .buttonStyle(ThemeButtonStyle())
                .themeTip("Save", key: "⌘S", detail: "Saves your changes and copies the image.")
                .padding(.leading, 4)
            Button("Copy") { Task { await model.copy() } }
                // In crop mode the crop bar's Crop is the next step, so Copy steps back to keep one main button (rule 1).
                .buttonStyle(ThemeButtonStyle(model.tool == .crop ? .secondary : .main))
                .themeTip("Copy", key: "⌘C", detail: "Copies the image with your changes, ready to paste.")
                .padding(.leading, 4)
        }
        .fixedSize()
    }
}

/// Fit to Content, Trim to Image and Background…, which opens the Style panel, where the background lives. The board's
/// "Canvas" with a 9 pt chevron on a toolbar button, or a 30 × 28 tile with the same menu when the title bar is short of
/// room.
private struct CanvasMenu: View {
    @Bindable var model: EditorModel
    let compact: Bool

    var body: some View {
        ThemeDropdown(title: "Canvas", entries: [
            .item("Fit to Content") { model.fitToContent() },
            .item("Trim to Image", enabled: model.document.canTrimToImage) { model.trimToImage() },
            .divider,
            .item("Background…") { model.showStylePanel() },
        ]) {
            if compact {
                Image(systemName: "rectangle.dashed").font(Theme.toolIcon)
            } else {
                HStack(spacing: 5) {
                    Text("Canvas")
                        .font(.scaled(12))
                        .foregroundStyle(ContrastAware(standard: Self.labelColor, increased: Theme.ink))
                    Image(systemName: "chevron.down")
                        .font(.scaled(9, weight: .bold))
                        .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
                }
            }
        }
        .buttonStyle(ThemeButtonStyle(.toolbar))
        .fixedSize()
        .themeTip("Canvas", detail: "Fit the canvas to what's on it, trim it to the image, or choose its background in the Style panel.")
    }

    /// The board's `#3A393F`, 85% ink, and the light ink at 85% in dark mode.
    private static let labelColor = Color(light: Color(hex: 0x16161A).opacity(0.85), dark: Color(hex: 0xEDEBE6).opacity(0.85))
}

/// Everything else you can do with the image: Copy Image, Copy Path, Save As…, Show in Finder and Pin to Screen.
private struct ShareMenu: View {
    let model: EditorModel

    var body: some View {
        ThemeDropdown(title: "Share", entries: entries) {
            HStack(spacing: 6) {
                Text("Share")
                Image(systemName: "chevron.down")
                    .font(.scaled(9, weight: .bold))
                    .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
            }
        }
        .buttonStyle(ThemeButtonStyle())
        .fixedSize()
        .themeTip("Share", detail: "Copy the file's path for an AI assistant or a chat, save a copy somewhere else, show it in Finder or pin it to your screen.")
    }

    private var entries: [ThemeMenuEntry] {
        EditorShareAction.allCases.flatMap { action -> [ThemeMenuEntry] in
            let item = ThemeMenuEntry.item(action.title, symbol: action.symbol, shortcut: action.shortcut) {
                Task { await model.share(action) }
            }
            return action.startsSection ? [.divider, item] : [item]
        }
    }
}

private extension EditorShareAction {
    var title: String {
        switch self {
        case .copyImage: String(localized: "Copy Image")
        case .copyPath: String(localized: "Copy Path")
        case .saveAs: String(localized: "Save As…")
        case .showInFinder: String(localized: "Show in Finder")
        case .pin: String(localized: "Pin to Screen")
        }
    }

    var symbol: String {
        switch self {
        case .copyImage: "doc.on.doc"
        case .copyPath: "sparkles"
        case .saveAs: "square.and.arrow.down"
        case .showInFinder: "folder"
        case .pin: "pin"
        }
    }
}

private struct CanvasHost: NSViewRepresentable {
    let canvas: EditorCanvasView

    func makeNSView(context: Context) -> EditorCanvasContainer { EditorCanvasContainer(canvas: canvas) }
    func updateNSView(_ nsView: EditorCanvasContainer, context: Context) {}
}
