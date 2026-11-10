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
                .fill(ContrastAware(standard: Brutal.hairline, increased: Brutal.ink.opacity(0.6)))
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
/// the middle, then Undo, Style, Layers, Share, Save and Copy, the one main button.
private struct EditorTitleBar: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.fileURL.lastPathComponent)
                    .font(Brutal.label)
                    .foregroundStyle(Brutal.ink)
                    .truncationMode(.middle)
                subtitle
                    .font(Brutal.caption)
                    .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .frame(minWidth: 100, maxWidth: 190, alignment: .leading)
            .padding(.leading, 8)
            // The name takes its room first; the tools sit centred in what's left.
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            EditorToolGroup(model: model)
            Spacer(minLength: 0)
            actions
        }
    }

    private var size: String { EditorToolbarLayout.sizeLabel(model.document.exportSize) }

    private var subtitle: Text {
        model.isDirty ? Text("Edited · \(size)") : Text(verbatim: size)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Tile(selected: false, help: "Undo", key: "⌘Z", detail: "Redo with ⇧⌘Z.", isEnabled: model.history.canUndo) {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward").font(Brutal.toolIcon)
            }
            Tile(
                selected: model.showsStylePanel, help: "Style",
                detail: "Shows a panel beside the canvas for the screenshot's background, padding, size, shadow and corners, or the selected image's, shape's or text's shadow and border."
            ) {
                model.toggleStylePanel()
            } label: {
                Image(systemName: "paintpalette").font(Brutal.toolIcon)
            }
            Tile(selected: model.showsLayers, help: "Layers", key: "⌘L", detail: "Shows every mark and image in a list beside the canvas.") {
                model.toggleLayers()
            } label: {
                Image(systemName: "sidebar.right").font(Brutal.toolIcon)
            }
            Rectangle()
                .fill(Brutal.controlEdge)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 6)
                .accessibilityHidden(true)
            ShareMenu(model: model)
            Button("Save") { Task { await model.save() } }
                .buttonStyle(BrutalButtonStyle())
                .brutalTip("Save", key: "⌘S", detail: "Saves your changes and copies the image.")
                .padding(.leading, 4)
            Button("Copy") { Task { await model.copy() } }
                // In crop mode the crop bar's Crop is the next step, so Copy steps back to keep one main button (rule 1).
                .buttonStyle(BrutalButtonStyle(model.tool == .crop ? .secondary : .main))
                .brutalTip("Copy", key: "⌘C", detail: "Copies the image with your changes, ready to paste.")
                .padding(.leading, 4)
        }
        .fixedSize()
    }
}

/// Everything else you can do with the image: Copy Image, Copy Path, Save As…, Show in Finder and Pin to Screen.
private struct ShareMenu: View {
    let model: EditorModel

    var body: some View {
        BrutalDropdown(title: "Share", entries: entries) {
            HStack(spacing: 6) {
                Text("Share")
                Image(systemName: "chevron.down")
                    .font(.scaled(9, weight: .bold))
                    .foregroundStyle(ContrastAware(standard: Brutal.secondaryText, increased: Brutal.ink))
            }
        }
        .buttonStyle(BrutalButtonStyle())
        .fixedSize()
        .brutalTip("Share", detail: "Copy the file's path for an AI assistant or a chat, save a copy somewhere else, show it in Finder or pin it to your screen.")
    }

    private var entries: [BrutalMenuEntry] {
        EditorShareAction.allCases.flatMap { action -> [BrutalMenuEntry] in
            let item = BrutalMenuEntry.item(action.title, symbol: action.symbol, shortcut: action.shortcut) {
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
