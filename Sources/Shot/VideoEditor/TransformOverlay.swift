import ShotCore
import SwiftUI

/// Handles over the player for the selected video clip: drag the box to move it, a corner to scale it, the knob to rotate it,
/// and double-click it to crop it. The picture follows when the drag ends, once the preview has been rebuilt. The box goes
/// round the part a crop leaves, which turns and scales about the whole picture's centre.
struct TransformOverlay: View {
    private static let handleSize: CGFloat = 12
    private static let knobDistance: CGFloat = 22

    private struct Origin {
        var values: PropertyValues
        var pointer: CGPoint
    }

    let model: VideoEditorModel
    @State private var origin: Origin?

    var body: some View {
        GeometryReader { geometry in
            if !model.isCropping, let clip = model.selectedClip, clip.size.height > 0, (clip.start...clip.end).contains(model.playhead) {
                let canvas = model.project.canvasSize
                let frame = model.shownFrame
                let fit = min(geometry.size.width / frame.width, geometry.size.height / frame.height)
                let topLeft = CGPoint(x: (geometry.size.width - frame.width * fit) / 2 - frame.minX * fit, y: (geometry.size.height - frame.height * fit) / 2 - frame.minY * fit)
                // Where the clip is now, with its keyframes applied.
                let transform = clip.transform(atTimeline: model.playhead)
                let scale = min(canvas.width / clip.size.width, canvas.height / clip.size.height) * transform.scale * fit
                let kept = LayerGeometry.keptRect(of: clip)
                let size = CGSize(width: kept.width * scale, height: kept.height * scale)
                // How far the part left's middle is from the whole picture's, before the turn.
                let shift = CGSize(width: (kept.midX - clip.size.width / 2) * scale, height: (kept.midY - clip.size.height / 2) * scale)
                let center = CGPoint(x: topLeft.x + (canvas.width / 2 + transform.offset.width) * fit, y: topLeft.y + (canvas.height / 2 + transform.offset.height) * fit)
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .inkBorder(Rectangle(), width: 2, color: Brutal.yellow)
                        .frame(width: size.width, height: size.height)
                        .onTapGesture {
                            if NSApp.currentEvent?.clickCount == 2 {
                                model.beginClipCrop(clip.id)
                            }
                        }
                        .gesture(move(clip, fit: fit))
                        .offset(shift)
                    ForEach(Array([(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].enumerated()), id: \.offset) { _, corner in
                        PartyColor(Brutal.yellow) { Rectangle().fill($0) }
                            .inkBorder(Rectangle(), width: 2)
                            .frame(width: Self.handleSize, height: Self.handleSize)
                            .offset(x: shift.width + corner.0 * size.width / 2, y: shift.height + corner.1 * size.height / 2)
                            .gesture(scaling(clip, center: center))
                    }
                    Circle()
                        .fill(Brutal.pink)
                        .inkBorder(Circle(), width: 2)
                        .frame(width: Self.handleSize, height: Self.handleSize)
                        .offset(x: shift.width, y: shift.height - size.height / 2 - Self.knobDistance)
                        .gesture(rotating(clip, center: center))
                }
                .rotationEffect(.radians(transform.rotation))
                .position(center)
            }
        }
        .coordinateSpace(name: "player")
        .allowsHitTesting(!model.isExporting)
    }

    private func drag(_ clip: Clip, update: @escaping (Origin, CGPoint) -> PropertyValues) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("player"))
            .onChanged { value in
                if origin == nil {
                    origin = Origin(values: clip.values(atTimeline: model.playhead), pointer: value.startLocation)
                    model.beginDrag()
                }
                if let origin {
                    model.setValues(update(origin, value.location), of: clip.id)
                }
            }
            .onEnded { _ in
                origin = nil
                model.endDrag()
            }
    }

    private func move(_ clip: Clip, fit: CGFloat) -> some Gesture {
        drag(clip) { origin, pointer in
            var moved = origin.values
            moved.position = CGSize(width: origin.values.position.width + (pointer.x - origin.pointer.x) / fit, height: origin.values.position.height + (pointer.y - origin.pointer.y) / fit)
            return moved
        }
    }

    private func scaling(_ clip: Clip, center: CGPoint) -> some Gesture {
        drag(clip) { origin, pointer in
            var scaled = origin.values
            let before = hypot(origin.pointer.x - center.x, origin.pointer.y - center.y)
            let now = hypot(pointer.x - center.x, pointer.y - center.y)
            scaled.scale = min(max(origin.values.scale * Double(now / max(before, 1)), PropertyValues.scaleRange.lowerBound), PropertyValues.scaleRange.upperBound)
            return scaled
        }
    }

    private func rotating(_ clip: Clip, center: CGPoint) -> some Gesture {
        drag(clip) { origin, pointer in
            var turned = origin.values
            let before = atan2(origin.pointer.y - center.y, origin.pointer.x - center.x)
            let now = atan2(pointer.y - center.y, pointer.x - center.x)
            turned.rotation = origin.values.rotation + Double(now - before)
            return turned
        }
    }
}
