import ShotCore
import SwiftUI

/// What the crop bar edits: the image editor's crop, or the video editor's crop of the frame or a clip.
@MainActor
protocol CropBarEditing: AnyObject, Observable {
    /// Whether crop mode is on, with a crop to adjust.
    var showsCropBar: Bool { get }
    /// The controls at the bottom left the bar keeps clear of, such as the image editor's zoom control.
    var cropBarFoot: CGSize { get }
    /// How much of the bottom the bar covers, which the picture keeps clear of.
    var cropBarClearance: CGFloat { get set }
    var cropAspect: CropAspect { get }
    func chooseCropAspect(_ aspect: CropAspect)
    /// The pixels applying the crop keeps, which the bar shows.
    var cropKeptSize: CGSize { get }
    var canResetCrop: Bool { get }
    func resetCrop()
    func cancelCrop()
    func applyCrop()
    /// What VoiceOver calls the bar.
    var cropBarName: LocalizedStringResource { get }
    /// What Reset's and Crop's tips say they do.
    var cropResetDetail: LocalizedStringResource { get }
    var cropApplyDetail: LocalizedStringResource { get }
}

/// Lays the crop bar over the canvas in crop mode, from Edit › Image editor · crop and combine: centred at the canvas's
/// foot, clear of the controls there. `CropBar.origin` decides where, and the picture fits above it.
struct CropBarOverlay<Model: CropBarEditing>: View {
    let model: Model
    @State private var barSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if model.showsCropBar {
                let origin = CropBar.origin(bar: barSize, in: proxy.size, foot: model.cropBarFoot, inset: CanvasFoot.inset)
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
        .animation(Motion.animation(.panelArrive, reduceMotion: reduceMotion), value: model.showsCropBar)
        .onChange(of: model.showsCropBar) {
            if !model.showsCropBar {
                model.cropBarClearance = 0
            }
        }
    }
}

/// Aspect, the size the crop keeps, Reset, then Cancel and Crop ↩, the crop's one main button.
private struct CropBarView<Model: CropBarEditing>: View {
    let model: Model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular)
        HStack(spacing: 10) {
            Text("Aspect")
                .font(.scaled(12, weight: .semibold))
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .accessibilityHidden(true)
            ThemeSegmented(
                selection: Binding(get: { model.cropAspect }, set: { model.chooseCropAspect($0) }),
                options: CropAspect.allCases.map { ($0, $0.label) }
            )
            .accessibilityLabel(Text("Aspect"))
            size
            Button("Reset") { model.resetCrop() }
                .buttonStyle(ThemeButtonStyle(.plain))
                .disabled(!model.canResetCrop)
                .themeTip("Reset", key: "⌫", detail: model.cropResetDetail)
            Rectangle()
                .fill(Theme.controlEdge)
                .frame(width: 1, height: 18)
                .accessibilityHidden(true)
            Button("Cancel") { model.cancelCrop() }
                .buttonStyle(ThemeButtonStyle(.secondary))
                .themeTip("Cancel", key: "esc", detail: "Leaves crop mode and keeps the crop as it was.")
            Button {
                model.applyCrop()
            } label: {
                HStack(spacing: 5) {
                    Text("Crop")
                    Text(verbatim: "↩").accessibilityHidden(true)
                }
            }
            .buttonStyle(ThemeButtonStyle(.main))
            .accessibilityLabel(Text("Crop"))
            .themeTip("Crop", key: "↩", detail: model.cropApplyDetail)
        }
        .padding(.vertical, 6)
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .depth(.float, fill: solid ? AnyShapeStyle(Theme.group) : AnyShapeStyle(cropBarFill), radius: Theme.Radius.group)
        .overlay {
            if contrast == .increased {
                Color.clear.inkBorder(shape, width: 1, color: Theme.ink.opacity(0.6))
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.cropBarName))
    }

    /// "1,480 × 560" in 11.5 pt bold mono, the pixels applying the crop keeps.
    private var size: some View {
        let kept = model.cropKeptSize
        let width = Int(kept.width.rounded()).formatted()
        let height = Int(kept.height.rounded()).formatted()
        return Text(verbatim: EditorToolbarLayout.sizeLabel(kept))
            .font(.scaled(11.5, weight: .bold, design: .monospaced, tabular: true))
            .foregroundStyle(ContrastAware(standard: Theme.ink.opacity(0.85), increased: Theme.ink))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Crop size"))
            .accessibilityValue(Text("\(width) by \(height) pixels"))
    }


    private var solid: Bool { contrast == .increased || reduceTransparency }
}

/// The board's fill, a touch see-through over the canvas. File-level, since a generic view can't store a static.
private let cropBarFill = Color(light: .white.opacity(0.96), dark: Color(hex: 0x2C2C30).opacity(0.96))

extension EditorModel: CropBarEditing {
    var showsCropBar: Bool { tool == .crop && cropDraft != nil }
    var cropBarFoot: CGSize { canvasFootLeading }
    var cropBarName: LocalizedStringResource { "Crop" }
    var cropResetDetail: LocalizedStringResource { "Takes the crop off, so the whole image is kept." }
    var cropApplyDetail: LocalizedStringResource { "Keeps what's inside the crop. Picking another tool, Copy or Save does too, and Undo takes it back." }
}
