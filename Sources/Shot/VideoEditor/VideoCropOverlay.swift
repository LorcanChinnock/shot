import AppKit
import ShotCoreApple
import SwiftUI

/// Crop mode over the player: the frame's crop on the canvas, or a clip's on its picture, turned and scaled with it.
/// The part cut off is dimmed, the handles resize the crop and dragging inside moves it; Shift keeps its shape.
/// Return applies it and Esc cancels, as in the image editor.
struct VideoCropOverlay: View {
    private static let handleSize: CGFloat = 12

    let model: VideoEditorModel
    @State private var dragStart: CGRect?

    var body: some View {
        GeometryReader { geometry in
            if let target = model.cropTarget, let draft = model.cropDraft, let bounds = model.cropBounds, let mapping = mapping(target, in: geometry.size) {
                ZStack {
                    // The cut-off part, dimmed: everything the crop can reach, less the crop.
                    Path { path in
                        path.addLines(corners(of: bounds).map(mapping.toView))
                        path.closeSubpath()
                        path.addLines(corners(of: draft).map(mapping.toView))
                        path.closeSubpath()
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    Path { path in
                        path.addLines(corners(of: draft).map(mapping.toView))
                        path.closeSubpath()
                    }
                    .fill(Color.white.opacity(0.001))
                    .gesture(drag(within: bounds, mapping: mapping) { start, from, to in
                        CropGeometry.move(start, dx: to.x - from.x, dy: to.y - from.y, within: bounds)
                    })
                    Path { path in
                        path.addLines(corners(of: draft).map(mapping.toView))
                        path.closeSubpath()
                    }
                    .stroke(Color.white, lineWidth: 2)
                    .allowsHitTesting(false)
                    ForEach(CropHandle.allCases, id: \.self) { handle in
                        PartyColor(Brutal.yellow) { Rectangle().fill($0) }
                            .inkBorder(Rectangle(), width: 2)
                            .frame(width: Self.handleSize, height: Self.handleSize)
                            .position(mapping.toView(handle.point(on: draft)))
                            .gesture(drag(within: bounds, mapping: mapping) { start, _, to in
                                let shift = NSEvent.modifierFlags.contains(.shift) && start.height > 0
                                let ratio = shift ? start.width / start.height : model.cropAspect.ratio(for: start.size)
                                return CropGeometry.resize(start, handle: handle, to: to, within: bounds, ratio: ratio)
                            })
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(target == .frame ? "Crop the frame" : "Crop the clip"))
            }
        }
        .coordinateSpace(name: "crop")
        .overlay(alignment: .top) {
            if model.isCropping {
                VideoCropBar(model: model)
                    .padding(.top, 8)
            }
        }
    }

    /// Maps the crop's own pixels to the view and back.
    private struct Mapping {
        var toView: (CGPoint) -> CGPoint
        var fromView: (CGPoint) -> CGPoint
    }

    /// The frame's crop is in canvas pixels; a clip's is in its picture's, placed as the clip is at the playhead.
    private func mapping(_ target: VideoCropTarget, in size: CGSize) -> Mapping? {
        let frame = model.shownFrame
        guard frame.width > 0, frame.height > 0 else {
            return nil
        }
        let fit = min(size.width / frame.width, size.height / frame.height)
        let toView = CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
            .concatenating(CGAffineTransform(scaleX: fit, y: fit))
            .concatenating(CGAffineTransform(translationX: (size.width - frame.width * fit) / 2, y: (size.height - frame.height * fit) / 2))
        let transform: CGAffineTransform
        switch target {
        case .frame:
            transform = toView
        case let .clip(id):
            guard var clip = model.project.clip(id) else {
                return nil
            }
            clip.transform = clip.transform(atTimeline: model.playhead)
            transform = LayerGeometry.transform(for: clip, canvas: model.project.canvasSize).concatenating(toView)
        }
        let inverse = transform.inverted()
        return Mapping(toView: { $0.applying(transform) }, fromView: { $0.applying(inverse) })
    }

    private func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    /// A drag that changes the crop from where it was when the drag began, given that, and where the pointer started
    /// and is now, in the crop's own pixels.
    private func drag(within bounds: CGRect, mapping: Mapping, change: @escaping (CGRect, CGPoint, CGPoint) -> CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("crop"))
            .onChanged { value in
                if dragStart == nil {
                    dragStart = model.cropDraft
                }
                if let start = dragStart {
                    model.cropDraft = change(start, mapping.fromView(value.startLocation), mapping.fromView(value.location))
                }
            }
            .onEnded { _ in
                dragStart = nil
            }
    }
}

/// What crop mode offers over the player: the shape, Reset, Cancel and Apply, and the size the crop comes out.
private struct VideoCropBar: View {
    let model: VideoEditorModel

    var body: some View {
        HStack(spacing: 8) {
            Text(model.cropTarget == .frame ? "CROP FRAME" : "CROP CLIP").sectionCaption()
            if let draft = model.cropDraft, model.cropTarget == .frame {
                let output = VideoFrameCrop.outputRect(crop: draft, canvas: model.project.canvasSize)
                Text(verbatim: "\(Int(output.width)) × \(Int(output.height))")
                    .font(Brutal.mono)
                    .foregroundStyle(Brutal.faded(0.75))
            }
            CropOptions(selected: model.cropAspect, canReset: model.cropDraft != model.cropBounds, choose: model.setCropAspect, reset: model.resetCropDraft)
            Button("Cancel") { model.cancelCrop() }
                .buttonStyle(BrutalButtonStyle(compact: true))
                .brutalTip("Leave the crop as it was (Esc)")
            PartyColor(Brutal.yellow) { color in
                Button("Apply") { model.applyCrop() }
                    .buttonStyle(BrutalButtonStyle(color: color, compact: true))
            }
            .brutalTip("Crop to this (Return)")
        }
        .padding(8)
        .glassCard()
    }
}
