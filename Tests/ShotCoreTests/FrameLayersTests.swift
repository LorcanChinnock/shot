import Foundation
import Testing
@testable import ShotCore

private func mark(at x: CGFloat, start: Double = 0, duration: Double = 10) -> AnnotationClip {
    let box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: x, y: 10, width: 40, height: 20)), color: RGBA.presets[0], lineWidth: 4)
    return AnnotationClip(annotation: box, start: start, duration: duration)
}

private func picture(_ name: String) -> FrameLayers.Source<String> {
    .picture(name, Clip(source: URL(fileURLWithPath: "/nowhere/\(name).mp4"), sourceDuration: 10, size: CGSize(width: 640, height: 360)))
}

/// Each layer, bottom to top: a picture by its name, and a run of annotations by where each is.
private func names(_ layers: [FrameLayers.Layer<String>]) -> [String] {
    layers.map { layer in
        switch layer {
        case let .picture(picture, _): picture
        case let .annotations(items): items.map(\.annotation).map(name).joined(separator: " ")
        }
    }
}

private func name(_ annotation: Annotation) -> String {
    guard case let .shape(_, rect) = annotation.kind else {
        return "?"
    }
    return "\(Int(rect.minX))"
}

private func layers(
    _ stack: [FrameLayers.Source<String>], at time: Double = 1, hidden: Set<UUID> = [], drawn: [AnnotationClip] = [], clipStyles: [UUID: ObjectStyle] = [:]
) -> [FrameLayers.Layer<String>] {
    FrameLayers.layers(of: stack, at: time, hidden: hidden, drawn: drawn, clipStyles: clipStyles)
}

@Test func annotationsBetweenPicturesDrawTogetherInRuns() {
    let stack: [FrameLayers.Source<String>] = [.annotation(mark(at: 0)), .annotation(mark(at: 100)), picture("low"), .annotation(mark(at: 200)), picture("high")]
    #expect(names(layers(stack)) == ["0 100", "low", "200", "high"])
    #expect(names(layers([])).isEmpty)
}

@Test func aPictureIsPlacedWhereItsKeyframesHaveItAndDrawnInItsLiveStyle() throws {
    var clip = Clip(source: URL(fileURLWithPath: "/nowhere/clip.mp4"), sourceDuration: 10, start: 1, size: CGSize(width: 640, height: 360))
    clip.animation.opacity = [Keyframe(time: 0, value: 1), Keyframe(time: 2, value: 0)]
    let style = ObjectStyle(border: Border(kind: .solid, lineWidth: 4))

    guard case let .picture(_, placed)? = layers([.picture("clip", clip)], at: 2).first else {
        Issue.record("expected the picture")
        return
    }
    #expect(placed.transform == clip.transform(atTimeline: 2))
    #expect(placed.transform.opacity < 1)
    #expect(placed.style.isEmpty)

    guard case let .picture(_, styled)? = layers([.picture("clip", clip)], at: 2, clipStyles: [clip.id: style]).first else {
        Issue.record("expected the picture")
        return
    }
    #expect(styled.style == style)
}

@Test func anAnnotationBeingEditedDrawsWhatsLiveInItsPlace() {
    let below = mark(at: 0), edited = mark(at: 100)
    var moved = edited
    moved.annotation = mark(at: 300).annotation
    let added = mark(at: 500)
    let stack: [FrameLayers.Source<String>] = [.annotation(below), .annotation(edited), picture("top")]

    // In its place in the stack, under the picture, with a new one on top of everything.
    #expect(names(layers(stack, hidden: [edited.id], drawn: [moved, added])) == ["0 300", "top", "500"])
    // Moved to where it isn't showing yet, it draws nowhere; a new one that isn't showing yet doesn't draw either.
    moved.start = 5
    #expect(names(layers(stack, hidden: [edited.id], drawn: [moved, mark(at: 500, start: 5)])) == ["0", "top"])
    // Hidden with nothing drawn in its place, as while it's deleted.
    #expect(names(layers(stack, hidden: [edited.id])) == ["0", "top"])
}

@Test func anAnnotationKeepsItsTurnAndFadeAtTheTime() {
    var turning = mark(at: 0)
    turning.animation.rotation = [Keyframe(time: 0, value: 0), Keyframe(time: 2, value: 1)]
    turning.animation.opacity = [Keyframe(time: 0, value: 1), Keyframe(time: 2, value: 0)]

    guard case let .annotations(items)? = layers([.annotation(turning)], at: 1).first, let item = items.first else {
        Issue.record("expected the annotation")
        return
    }
    let state = turning.rendered(atTimeline: 1)
    #expect(item == AnnotationFrame.Item(annotation: state.annotation, rotation: state.rotation, opacity: state.opacity))
    #expect(!item.isPlain)
}
