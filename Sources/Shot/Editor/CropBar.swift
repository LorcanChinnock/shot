import ShotCore
import SwiftUI

/// Lays the crop bar over the canvas in crop mode, from Edit › Image editor · crop and combine: centred at the canvas's
/// foot, clear of the zoom control. `CropBar.origin` decides where, and the canvas fits the image above it.
struct CropBarOverlay: View {
    @Bindable var model: EditorModel
    @State private var barSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shows: Bool { model.tool == .crop && model.cropDraft != nil }

    var body: some View {
        GeometryReader { proxy in
            if shows {
                let origin = CropBar.origin(bar: barSize, in: proxy.size, foot: model.canvasFootLeading, inset: CanvasFoot.inset)
                CropBarView(model: model)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self, of: \.size) { barSize = $0 }
                    // Hidden for the one layout before its size is known, so it never shows in the wrong place.
                    .opacity(barSize == .zero ? 0 : 1)
                    .offset(x: origin.x, y: origin.y)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                    .onChange(of: CropBar.clearance(origin: origin, in: proxy.size), initial: true) { _, clearance in
                        model.cropBarClearance = barSize == .zero ? 0 : clearance
                    }
            }
        }
        .animation(Motion.animation(.panelArrive, reduceMotion: reduceMotion), value: shows)
        .onChange(of: shows) {
            if !shows {
                model.cropBarClearance = 0
            }
        }
    }
}

/// Aspect, the size the crop keeps, Reset, then Cancel and Crop ↩, the crop's one main button.
private struct CropBarView: View {
    @Bindable var model: EditorModel
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brutal.Radius.group, style: .circular)
        HStack(spacing: 10) {
            Text("Aspect")
                .font(.scaled(12, weight: .semibold))
                .foregroundStyle(ContrastAware(standard: Brutal.tertiaryText, increased: Brutal.ink))
                .accessibilityHidden(true)
            BrutalSegmented(
                selection: Binding(get: { model.cropAspect }, set: { model.chooseCropAspect($0) }),
                options: CropAspect.allCases.map { ($0, $0.label) }
            )
            .accessibilityLabel(Text("Aspect"))
            size
            Button("Reset", action: model.resetCrop)
                .buttonStyle(BrutalButtonStyle(.plain))
                .disabled(!model.canResetCrop)
                .brutalTip("Reset", key: "⌫", detail: "Takes the crop off, so the whole image is kept.")
            Rectangle()
                .fill(Brutal.controlEdge)
                .frame(width: 1, height: 18)
                .accessibilityHidden(true)
            Button("Cancel", action: model.cancelCrop)
                .buttonStyle(BrutalButtonStyle(.secondary))
                .brutalTip("Cancel", key: "esc", detail: "Leaves crop mode and keeps the crop as it was.")
            Button(action: model.applyCrop) {
                HStack(spacing: 5) {
                    Text("Crop")
                    Text(verbatim: "↩").accessibilityHidden(true)
                }
            }
            .buttonStyle(BrutalButtonStyle(.main))
            .accessibilityLabel(Text("Crop"))
            .brutalTip("Crop", key: "↩", detail: "Keeps what's inside the crop. Picking another tool, Copy or Save does too, and Undo takes it back.")
        }
        .padding(.vertical, 6)
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .depth(.float, fill: solid ? AnyShapeStyle(Brutal.group) : AnyShapeStyle(Self.fill), radius: Brutal.Radius.group)
        .overlay {
            if contrast == .increased {
                Color.clear.inkBorder(shape, width: 1, color: Brutal.ink.opacity(0.6))
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Crop"))
    }

    /// "1,480 × 560" in 11.5 pt bold mono, the pixels applying the crop keeps.
    private var size: some View {
        let kept = model.cropKeptSize
        let width = Int(kept.width.rounded()).formatted()
        let height = Int(kept.height.rounded()).formatted()
        return Text(verbatim: EditorToolbarLayout.sizeLabel(kept))
            .font(.scaled(11.5, weight: .bold, design: .monospaced, tabular: true))
            .foregroundStyle(ContrastAware(standard: Brutal.ink.opacity(0.85), increased: Brutal.ink))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Crop size"))
            .accessibilityValue(Text("\(width) by \(height) pixels"))
    }

    /// The board's fill, a touch see-through over the canvas.
    private static let fill = Color(light: .white.opacity(0.96), dark: Color(hex: 0x2C2C30).opacity(0.96))

    private var solid: Bool { contrast == .increased || reduceTransparency }
}
