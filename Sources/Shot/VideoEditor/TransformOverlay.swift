import ShotCore
import SwiftUI

/// Handles over the player for the selected video clip: drag the box to move it, a corner to scale it, the knob to rotate it.
/// The picture follows when the drag ends, once the preview has been rebuilt.
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
            if let clip = model.selectedClip, clip.size.height > 0, (clip.start...clip.end).contains(model.playhead) {
                let canvas = model.project.canvasSize
                let fit = min(geometry.size.width / canvas.width, geometry.size.height / canvas.height)
                let topLeft = CGPoint(x: (geometry.size.width - canvas.width * fit) / 2, y: (geometry.size.height - canvas.height * fit) / 2)
                // Where the clip is now, with its keyframes applied.
                let transform = clip.transform(atTimeline: model.playhead)
                let scale = min(canvas.width / clip.size.width, canvas.height / clip.size.height) * transform.scale * fit
                let size = CGSize(width: clip.size.width * scale, height: clip.size.height * scale)
                let center = CGPoint(x: topLeft.x + (canvas.width / 2 + transform.offset.width) * fit, y: topLeft.y + (canvas.height / 2 + transform.offset.height) * fit)
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .overlay(Rectangle().strokeBorder(Brutal.yellow, lineWidth: 2))
                        .frame(width: size.width, height: size.height)
                        .gesture(move(clip, fit: fit))
                    ForEach(Array([(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].enumerated()), id: \.offset) { _, corner in
                        Rectangle()
                            .fill(Brutal.yellow)
                            .inkBorder(Rectangle(), width: 2)
                            .frame(width: Self.handleSize, height: Self.handleSize)
                            .offset(x: corner.0 * size.width / 2, y: corner.1 * size.height / 2)
                            .gesture(scaling(clip, center: center))
                    }
                    Circle()
                        .fill(Brutal.pink)
                        .inkBorder(Circle(), width: 2)
                        .frame(width: Self.handleSize, height: Self.handleSize)
                        .offset(y: -size.height / 2 - Self.knobDistance)
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
            scaled.scale = min(max(origin.values.scale * Double(now / max(before, 1)), 0.05), 20)
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
