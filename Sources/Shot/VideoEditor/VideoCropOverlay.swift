import AppKit
import ShotCore
import SwiftUI

/// Crop mode over the player: the frame's crop on the canvas, or a clip's on its picture, turned and scaled with it. It
/// takes the image editor's look from Edit › Image editor · crop and combine: a wash of the well's colour outside the
/// crop, an ink outline with a thirds grid, and ink corners and side bars. The corners and sides resize the crop and
/// dragging inside moves it; Shift keeps its shape. The crop bar at the well's foot (`CropBarOverlay`) applies it.
struct VideoCropOverlay: View {
    /// The square round each corner and side that catches the pointer.
    private static let hitSize: CGFloat = 24

    let model: VideoEditorModel
    @State private var dragStart: CGRect?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            if let target = model.cropTarget, let draft = model.cropDraft, let bounds = model.cropBounds, let mapping = mapping(target, in: geometry.size) {
                let box = mapping.box(draft)
                let local = CGRect(origin: .zero, size: box.size)
                let increased = contrast == .increased
                ZStack {
                    // What the crop leaves out, washed in the well's colour: everything the crop can reach, less the crop.
                    Path { path in
                        path.addLines(corners(of: bounds).map(mapping.toView))
                        path.closeSubpath()
                        path.addLines(corners(of: draft).map(mapping.toView))
                        path.closeSubpath()
                    }
                    .fill(VideoEditorSurface.well.opacity(increased ? 0.85 : 0.72), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    // The crop, turned with the clip it crops.
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .gesture(drag(within: bounds, mapping: mapping) { start, from, to in
                                CropGeometry.move(start, dx: to.x - from.x, dy: to.y - from.y, within: bounds)
                            })
                        CropFrameMarks(size: box.size, increased: increased)
                            .allowsHitTesting(false)
                        ForEach(CropHandle.allCases, id: \.self) { handle in
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: Self.hitSize, height: Self.hitSize)
                                .position(handle.point(on: local))
                                .gesture(drag(within: bounds, mapping: mapping) { start, _, to in
                                    let shift = NSEvent.modifierFlags.contains(.shift) && start.height > 0
                                    let ratio = shift ? start.width / start.height : model.cropAspect.ratio(for: start.size)
                                    return CropGeometry.resize(start, handle: handle, to: to, within: bounds, ratio: ratio)
                                })
                        }
                    }
                    .frame(width: box.size.width, height: box.size.height)
                    .rotationEffect(.radians(box.angle))
                    .position(box.center)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(model.cropBarName))
            }
        }
        .coordinateSpace(name: "crop")
    }

    /// Maps the crop's own pixels to the view and back.
    private struct Mapping {
        var transform: CGAffineTransform

        func toView(_ point: CGPoint) -> CGPoint { point.applying(transform) }
        func fromView(_ point: CGPoint) -> CGPoint { point.applying(transform.inverted()) }

        /// Where `rect` lands in the view: its centre, its size in view points and its turn. The mapping only scales,
        /// turns and moves, so the rect stays a rectangle.
        func box(_ rect: CGRect) -> (center: CGPoint, size: CGSize, angle: CGFloat) {
            let scale = hypot(transform.a, transform.b)
            return (toView(CGPoint(x: rect.midX, y: rect.midY)), CGSize(width: rect.width * scale, height: rect.height * scale), atan2(transform.b, transform.a))
        }
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
        switch target {
        case .frame:
            return Mapping(transform: toView)
        case let .clip(id):
            guard var clip = model.project.clip(id) else {
                return nil
            }
            clip.transform = clip.transform(atTimeline: model.playhead)
            return Mapping(transform: LayerGeometry.transform(for: clip, canvas: model.project.canvasSize).concatenating(toView))
        }
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

/// The crop's outline, thirds grid, corners and side bars in a crop of `size` view points, as the image editor's canvas
/// draws them: a 1.5 pt ink outline inside the edge with a 1 pt edge of the opposite colour outside it, white thirds at
/// 80%, and ink marks with the same opposite edge, so they show on any picture. Dark mode draws the light ink.
private struct CropFrameMarks: View {
    let size: CGSize
    let increased: Bool

    private static let ink = Color(light: Brutal.line, dark: Color(hex: 0xEDEBE6))
    private static let edge = Color(light: .white, dark: .black)

    var body: some View {
        let crop = CGRect(origin: .zero, size: size)
        ZStack(alignment: .topLeading) {
            Path { path in
                for third in [1.0 / 3, 2.0 / 3] {
                    path.addRect(CGRect(x: crop.width * third - 0.5, y: 0, width: 1, height: crop.height))
                    path.addRect(CGRect(x: 0, y: crop.height * third - 0.5, width: crop.width, height: 1))
                }
            }
            .fill(Color.white.opacity(increased ? 1 : 0.8))
            Path(crop.insetBy(dx: -0.5, dy: -0.5)).stroke(Self.edge, lineWidth: 1)
            Path(crop.insetBy(dx: 0.75, dy: 0.75)).stroke(Self.ink, lineWidth: 1.5)
            let marks = marks(crop)
            marks.stroke(Self.edge, lineWidth: 2)
            marks.fill(Self.ink)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func marks(_ crop: CGRect) -> Path {
        var path = Path()
        for corner in CropMarks.corners(of: crop) {
            path.addLines(corner)
            path.closeSubpath()
        }
        for bar in CropMarks.bars(of: crop) {
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: CropMarks.barRadius, height: CropMarks.barRadius), style: .circular)
        }
        return path
    }
}

extension VideoEditorModel: CropBarEditing {
    var showsCropBar: Bool { isCropping && cropDraft != nil }

    /// The drawing tools' column, 40 pt wide at the well's left, while a crop started from them keeps it showing.
    var cropBarFoot: CGSize { showsDrawTools ? CGSize(width: 40, height: 0) : .zero }

    var cropKeptSize: CGSize {
        guard let cropDraft else {
            return .zero
        }
        return CropBar.keptSize(videoDraft: cropDraft, croppingFrame: cropTarget == .frame, canvas: project.canvasSize)
    }

    var canResetCrop: Bool { cropDraft != nil && cropDraft != cropBounds }

    // Each branch returns its own literal, since a ternary's second branch isn't extracted for translation.
    var cropBarName: LocalizedStringResource {
        if cropTarget == .frame {
            return "Crop Frame"
        }
        return "Crop Clip"
    }

    var cropResetDetail: LocalizedStringResource {
        if cropTarget == .frame {
            return "Shows the whole frame again, so nothing is cropped off."
        }
        return "Shows the clip's whole picture again, so nothing is cropped off."
    }

    var cropApplyDetail: LocalizedStringResource { "Keeps what's inside the crop. Undo takes it back." }
}
