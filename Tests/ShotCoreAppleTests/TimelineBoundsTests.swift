import CoreGraphics
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

private let recording = URL(fileURLWithPath: "/tmp/recording.mov")
private let canvas = CGSize(width: 640, height: 360)

private func project() -> Project {
    Project(source: recording, duration: 10, canvasSize: canvas, hasAudio: true)
}

private func box() -> Annotation {
    Annotation(kind: .shape(.rectangle, rect: CGRect(x: 100, y: 100, width: 100, height: 60)), color: RGBA.presets[0], lineWidth: 4)
}

@Test func annotationsAreAnimatedLikeClips() throws {
    var (annotated, id) = project().adding(annotation: box(), at: 2)
    annotated = try #require(annotated.applying(.fadeIn, toClip: id))
    let state = try #require(annotated.annotationClip(id)).rendered(atTimeline: 2.25)
    // A quarter of a second into a half-second fade that eases out is three quarters of the way.
    #expect(abs(state.opacity - 0.75) < 1e-9 && state.rotation == 0)
    var values = try #require(annotated.values(ofClip: id, at: 3))
    values.position = CGSize(width: 30, height: 10)
    let moved = try #require(annotated.setting(values: values, ofClip: id, at: 3))
    let drawn = try #require(moved.annotationClip(id)).rendered(atTimeline: 3).annotation
    #expect(drawn.bounds == CGRect(x: 130, y: 110, width: 100, height: 60))
}

@Test func scalingAnAnnotationKeepsItsCentre() {
    let scaled = box().scaled(by: 2)
    #expect(scaled.bounds == CGRect(x: 50, y: 70, width: 200, height: 120))
    #expect(scaled.lineWidth == 8)
    let original = box()
    #expect(original.scaled(by: 1) == original)
    #expect(original.scaled(by: 0) == original)
}

@Test func scalingEveryKindGrowsItsBounds() {
    let kinds: [Annotation.Kind] = [
        .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 60)), .line(from: .zero, to: CGPoint(x: 80, y: 40)),
        .shape(.ellipse, rect: CGRect(x: 0, y: 0, width: 60, height: 40)), .blur(CGRect(x: 5, y: 5, width: 50, height: 30)),
        .freehand([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 20), CGPoint(x: 90, y: 0)]),
        .text("Hi", origin: CGPoint(x: 20, y: 20), fontSize: 24), .counter(3, center: CGPoint(x: 50, y: 50)),
        .note("A note", rect: CGRect(x: 10, y: 10, width: 200, height: 40)),
    ]
    for kind in kinds {
        let annotation = Annotation(kind: kind, color: RGBA.presets[0], lineWidth: 4)
        let big = annotation.scaled(by: 2)
        #expect(big.bounds.width > annotation.bounds.width * 1.4, "\(kind)")
        // A note's height follows its wrapped text, so only its rectangle, not its frame, keeps the centre.
        if case .note = kind { continue }
        #expect(abs(big.bounds.midX - annotation.bounds.midX) < 1.5 && abs(big.bounds.midY - annotation.bounds.midY) < 1.5, "\(kind) keeps its centre")
    }
}
