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
                Button { model.toggleLayers() } label: { Label("Layers", systemImage: "square.3.layers.3d").fixedSize() }
                    .buttonStyle(BrutalButtonStyle(color: model.showsLayers ? Brutal.violet : .white, compact: true))
                    .brutalTip("Show the layers (⌘L)")
                ZoomMenu(model: model, canvas: canvas)
                CanvasMenu(model: model)
                Button("Copy") { Task { await model.copy() } }
                    .buttonStyle(BrutalButtonStyle(compact: true))
                    .brutalTip("Copy image (⌘C)")
                PartyColor(Brutal.yellow) { color in
                    Button("Save") { Task { await model.save() } }
                        .buttonStyle(BrutalButtonStyle(color: color, compact: true))
                }
                .brutalTip("Save and copy (⌘S)")
            }
            .padding(.leading, GlassWindow.trafficLightsWidth)
            .frame(height: GlassWindow.titlebarHeight)
            .padding(.bottom, -Brutal.sectionGap / 2)
            EditorToolbar(model: model)
            HStack(spacing: Brutal.sectionGap) {
                CanvasHost(canvas: canvas)
                    .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular))
                    .glassCard()
                if model.showsLayers {
                    LayersPanel(
                        rows: model.layerRows,
                        selection: Binding(get: { model.selectedIDs }, set: { model.selectLayers($0) }),
                        onMove: model.moveLayers,
                        onHide: { model.setHidden($1, $0) },
                        onLock: { model.setLocked($1, $0) },
                        onDuplicate: model.duplicateLayers,
                        onDelete: model.deleteLayers
                    )
                }
            }
        }
        .padding([.horizontal, .bottom], Brutal.windowInset)
    }
}

private struct CanvasHost: NSViewRepresentable {
    let canvas: EditorCanvasView

    func makeNSView(context: Context) -> EditorCanvasView { canvas }
    func updateNSView(_ nsView: EditorCanvasView, context: Context) {}
}

/// Shows the zoom and offers the zoom commands; pinch and the keyboard shortcuts do the same.
private struct ZoomMenu: View {
    @Bindable var model: EditorModel
    let canvas: EditorCanvasView

    var body: some View {
        BrutalDropdown(title: "Zoom", entries: [
            .item("Zoom In", shortcut: "⌘+") { canvas.zoomIn() },
            .item("Zoom Out", shortcut: "⌘-") { canvas.zoomOut() },
            .divider,
            .item("Zoom to Fit", shortcut: "⌘0") { canvas.zoomToFit() },
            .item("Actual Size", shortcut: "⌘1") { canvas.zoomToActualSize() },
        ]) {
            HStack(spacing: 6) {
                Text("\(Int((model.zoom * 100).rounded()))%")
                    .monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
            }
        }
        .buttonStyle(BrutalButtonStyle(compact: true))
        .fixedSize()
        .brutalTip("Zoom in (⌘+), out (⌘-), to fit (⌘0) or to actual size (⌘1). Pinch to zoom; scroll, Space-drag, middle-drag or the hand tool (H) to move around.")
    }
}

private struct CanvasMenu: View {
    private static let white = RGBA(1, 1, 1)

    @Bindable var model: EditorModel

    var body: some View {
        BrutalDropdown(title: "Canvas", entries: [
            .item("Fit to Content") { model.fitToContent() },
            .item("Trim to Image", enabled: !model.document.capturePaintedBounds.contains(model.document.canvasRect)) { model.trimToImage() },
            .divider,
            .header("Background"),
        ] + backgrounds.map { name, color in
            .item(name, selected: model.document.background == color) { model.setBackground(color) }
        }) {
            HStack(spacing: 6) {
                Text("Canvas")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .black))
            }
        }
        .buttonStyle(BrutalButtonStyle(compact: true))
        .fixedSize()
        .brutalTip("Canvas size and background")
    }

    private var backgrounds: [(name: String, color: RGBA?)] {
        // JPEG has no alpha, so it can't keep transparent padding.
        (model.isJPEG ? [] : [("Transparent", nil)]) + [("White", Self.white)]
            + RGBA.presets.indices.filter { RGBA.presets[$0] != Self.white }.map { (EditorToolbar.colorNames[$0], RGBA.presets[$0]) }
    }
}
