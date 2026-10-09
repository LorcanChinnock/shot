import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let recording = URL(fileURLWithPath: "/tmp/recording.mov")
private let canvas = CGSize(width: 640, height: 360)
private let overlay = ImportedMedia(source: URL(fileURLWithPath: "/tmp/overlay.mov"), duration: 4, size: CGSize(width: 64, height: 36), hasAudio: true)

private func project() -> Project {
    Project(source: recording, duration: 10, canvasSize: canvas, hasAudio: true)
}

private func withOverlay(at start: Double = 2) throws -> (project: Project, id: UUID) {
    let (imported, id) = try #require(project().importing(overlay, at: start))
    return (imported, id)
}

private func box() -> Annotation {
    Annotation(kind: .shape(.rectangle, rect: CGRect(x: 100, y: 100, width: 100, height: 60)), color: RGBA.presets[0], lineWidth: 4)
}

@Test func settingAPropertyWithoutKeyframesChangesItForGood() throws {
    let (imported, id) = try withOverlay()
    var values = try #require(imported.values(ofClip: id, at: 3))
    values.scale = 0.5
    let changed = try #require(imported.setting(values: values, ofClip: id, at: 3))
    #expect(changed.clip(id)?.transform.scale == 0.5)
    #expect(changed.clip(id)?.animation.isEmpty == true)
    #expect(changed.values(ofClip: id, at: 2.1)?.scale == 0.5)
}

@Test func settingAPropertyThatHasKeyframesAddsOneAtTheTime() throws {
    var (imported, id) = try withOverlay()
    imported = try #require(imported.togglingKeyframe(.scale, ofClip: id, at: 2))
    var values = try #require(imported.values(ofClip: id, at: 4))
    values.scale = 2
    let changed = try #require(imported.setting(values: values, ofClip: id, at: 4))
    let animation = try #require(changed.clip(id)?.animation)
    #expect(animation.scale.map(\.time) == [0, 2] && animation.scale.map(\.value) == [1, 2])
    #expect(changed.clip(id)?.transform.scale == 1, "the plain value is untouched")
    #expect(changed.values(ofClip: id, at: 3)?.scale == 1.5)
}

@Test func settingOnlyChangesWhatDiffers() throws {
    var (imported, id) = try withOverlay()
    imported = try #require(imported.togglingKeyframe(.opacity, ofClip: id, at: 2))
    var values = try #require(imported.values(ofClip: id, at: 3))
    values.position = CGSize(width: 40, height: 0)
    let changed = try #require(imported.setting(values: values, ofClip: id, at: 3))
    #expect(changed.clip(id)?.transform.offset == CGSize(width: 40, height: 0))
    #expect(changed.clip(id)?.animation.position.isEmpty == true)
    #expect(changed.clip(id)?.animation.opacity.count == 1)
}

@Test func volumeIsClampedAndKeyframeableOnSound() throws {
    let (imported, _) = try withOverlay()
    let sound = imported.tracks[3].clips[0]
    var values = sound.propertyValues
    values.volume = 5
    #expect(imported.setting(values: values, ofClip: sound.id, at: 3)?.clip(sound.id)?.volume == 2)
}

@Test func togglingAKeyframeAddsThenRemovesIt() throws {
    let (imported, id) = try withOverlay()
    let added = try #require(imported.togglingKeyframe(.opacity, ofClip: id, at: 3))
    #expect(added.clip(id)?.animation.opacity == [Keyframe(time: 1, value: 1)])
    #expect(added.trimEdit == nil)
    let removed = try #require(added.togglingKeyframe(.opacity, ofClip: id, at: 3))
    #expect(removed.clip(id)?.animation.isEmpty == true)
}

@Test func keyframesBeforeTheClipStartLandOnItsFirstFrame() throws {
    let (imported, id) = try withOverlay()
    let added = try #require(imported.togglingKeyframe(.scale, ofClip: id, at: 0.5))
    #expect(added.clip(id)?.animation.scale.map(\.time) == [0])
}

@Test func keyframesCanBeEasedMovedAndRemovedByTime() throws {
    var (imported, id) = try withOverlay()
    imported = try #require(imported.togglingKeyframe(.scale, ofClip: id, at: 2))
    imported = try #require(imported.togglingKeyframe(.scale, ofClip: id, at: 4))
    imported = try #require(imported.settingEasing(.spring, ofClip: id, at: 0))
    #expect(imported.animation(ofClip: id)?.easing(at: 0) == .spring)
    imported = try #require(imported.movingKeyframes(ofClip: id, from: 2, to: 3))
    #expect(imported.animation(ofClip: id)?.scale.map(\.time) == [0, 3])
    imported = try #require(imported.movingKeyframes(ofClip: id, from: 3, to: 99))
    #expect(imported.animation(ofClip: id)?.scale.map(\.time) == [0, 4], "kept inside the clip")
    imported = try #require(imported.removingKeyframes(ofClip: id, at: 0))
    #expect(imported.animation(ofClip: id)?.scale.map(\.time) == [4])
}

@Test func splittingAClipSplitsItsKeyframesAndKeepsTheCurve() throws {
    var (imported, id) = try withOverlay(at: 0)
    imported = try #require(imported.togglingKeyframe(.opacity, ofClip: id, at: 0))
    var values = try #require(imported.values(ofClip: id, at: 4))
    values.opacity = 0
    imported = try #require(imported.setting(values: values, ofClip: id, at: 4))
    let split = try #require(imported.splitting(at: 2))
    let halves = split.tracks[2].clips
    #expect(halves.count == 2)
    #expect(halves[0].animation.opacity.map(\.time) == [0, 2] && abs(halves[0].animation.opacity.last!.value - 0.5) < 1e-9)
    #expect(halves[1].animation.opacity.map(\.time) == [0, 2] && abs(halves[1].animation.opacity.first!.value - 0.5) < 1e-9)
    // The second half carries on from where the first stopped.
    #expect(abs((split.values(ofClip: halves[1].id, at: 3)?.opacity ?? 9) - 0.25) < 1e-9)
}

@Test func trimmingTheStartKeepsKeyframesOnTheSameFrames() throws {
    var (imported, id) = try withOverlay(at: 0)
    imported = try #require(imported.togglingKeyframe(.scale, ofClip: id, at: 3))
    let trimmed = try #require(imported.trimming(clip: id, .start, toTimeline: 1))
    #expect(trimmed.clip(id)?.animation.scale.map(\.time) == [2], "3 s in the timeline is 2 s into the trimmed clip")
}

@Test func trimmingAnAnnotationsStartShiftsItsKeyframesToo() throws {
    var (annotated, id) = project().adding(annotation: box(), at: 2)
    annotated = try #require(annotated.togglingKeyframe(.opacity, ofClip: id, at: 4))
    let trimmed = try #require(annotated.trimming(clip: id, .start, toTimeline: 3))
    #expect(trimmed.annotationClip(id)?.animation.opacity.map(\.time) == [1])
}

@Test func presetsFillInKeyframesForTheClipsLength() throws {
    let (imported, id) = try withOverlay()
    let faded = try #require(imported.applying(.fadeIn, toClip: id))
    #expect(faded.clip(id)?.animation.opacity.map(\.time) == [0, 0.5] && faded.clip(id)?.animation.opacity.map(\.value) == [0, 1])
    let both = try #require(faded.applying(.fadeOut, toClip: id))
    #expect(both.clip(id)?.animation.opacity.map(\.time) == [0, 0.5, 3.5, 4])
    #expect(both.clip(id)?.animation.opacity.map(\.value) == [0, 1, 1, 0])
    #expect(both.values(ofClip: id, at: 4)?.opacity == 1, "2 s into the clip")
    #expect(both.values(ofClip: id, at: 2)?.opacity == 0 && both.values(ofClip: id, at: 6)?.opacity == 0)
}

@Test func popAndSlideInAnimateScaleAndPosition() throws {
    let (imported, id) = try withOverlay()
    let popped = try #require(imported.applying(.pop, toClip: id))
    let scale = try #require(popped.clip(id)?.animation.scale)
    #expect(scale.count == 2 && abs(scale[0].value - 0.2) < 1e-9 && scale[1].value == 1 && scale[0].easing == .spring)
    let slid = try #require(imported.applying(.slideIn, toClip: id))
    let start = try #require(slid.values(ofClip: id, at: 2)?.position)
    #expect(start.width < -100 && slid.values(ofClip: id, at: 3)?.position == .zero)
}

@Test func presetsOnAShortClipFitInsideIt() throws {
    var short = overlay
    short.duration = 0.4
    let (imported, id) = try #require(project().importing(short, at: 0))
    let faded = try #require(imported.applying(.fadeIn, toClip: id))
    #expect(faded.clip(id)?.animation.opacity.map(\.time) == [0, 0.2])
}

@Test func aPresetKeepsWhatWasSetByHand() throws {
    var (imported, id) = try withOverlay()
    imported = try #require(imported.togglingKeyframe(.opacity, ofClip: id, at: 3))
    var values = try #require(imported.values(ofClip: id, at: 3))
    values.opacity = 0.6
    imported = try #require(imported.setting(values: values, ofClip: id, at: 3))
    let faded = try #require(imported.applying(.fadeIn, toClip: id))
    #expect(faded.clip(id)?.animation.opacity.map(\.time) == [0, 0.5, 1])
    #expect(faded.clip(id)?.animation.opacity.last?.value == 0.6, "the hand-set keyframe stays")
    #expect(faded.clip(id)?.animation.opacity[1].value == 0.6, "it fades up to what's there")
}

@Test func drawOnNeedsAnArrowLineOrPenStroke() throws {
    let (imported, id) = try withOverlay()
    #expect(!imported.supports(.drawOn, forClip: id))
    #expect(imported.supports(.pop, forClip: id))
    let (withBox, boxID) = project().adding(annotation: box(), at: 1)
    #expect(!withBox.supports(.drawOn, forClip: boxID) && withBox.supports(.fadeIn, forClip: boxID))
    let arrow = Annotation(kind: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)), color: RGBA.presets[0], lineWidth: 4)
    let (withArrow, arrowID) = project().adding(annotation: arrow, at: 1)
    #expect(withArrow.supports(.drawOn, forClip: arrowID))
    let drawn = try #require(withArrow.applying(.drawOn, toClip: arrowID))
    #expect(drawn.annotationClip(arrowID)?.animation.reveal.map(\.value) == [0, 1])
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

@Test func revealingDrawsPartOfAnArrowLineOrStroke() {
    let arrow = Annotation(kind: .arrow(from: .zero, to: CGPoint(x: 100, y: 0)), color: RGBA.presets[0], lineWidth: 4)
    guard case let .arrow(_, end) = arrow.revealed(0.25).kind else {
        Issue.record("not an arrow")
        return
    }
    #expect(end == CGPoint(x: 25, y: 0))
    #expect(arrow.revealed(1) == arrow && arrow.revealed(7) == arrow)
    let line = Annotation(kind: .line(from: .zero, to: CGPoint(x: 0, y: 80)), color: RGBA.presets[0], lineWidth: 4)
    guard case let .line(_, lineEnd) = line.revealed(0.5).kind else {
        Issue.record("not a line")
        return
    }
    #expect(lineEnd == CGPoint(x: 0, y: 40))
    let shape = box()
    #expect(shape.revealed(0.1) == shape, "shapes are drawn whole")
}

@Test func revealingAStrokeKeepsPointsToTheLengthAlongIt() {
    let stroke = Annotation(kind: .freehand([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]), color: RGBA.presets[0], lineWidth: 4)
    guard case let .freehand(points) = stroke.revealed(0.75).kind else {
        Issue.record("not a stroke")
        return
    }
    #expect(points == [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 50)])
    guard case let .freehand(none) = stroke.revealed(0).kind else {
        Issue.record("not a stroke")
        return
    }
    #expect(none.first == CGPoint(x: 0, y: 0) && none.count == 2 && none.last == none.first)
}

@Test func animatedProjectsRoundTripThroughJSON() throws {
    var (imported, id) = try withOverlay()
    imported = try #require(imported.applying(.pop, toClip: id))
    let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(imported))
    #expect(decoded == imported)
}

@Test func aProjectWithAnimatedMainClipIsNotATrimEdit() throws {
    let plain = project()
    let id = plain.main.clips[0].id
    let animated = try #require(plain.togglingKeyframe(.scale, ofClip: id, at: 2))
    #expect(plain.trimEdit != nil && animated.trimEdit == nil)
    let soundID = plain.tracks[1].clips[0].id
    #expect(try #require(plain.togglingKeyframe(.volume, ofClip: soundID, at: 2)).trimEdit == nil)
}

@Test func eachKindOfClipKeysItsOwnProperties() {
    let base = project()
    #expect(base.keyableProperties(ofClip: base.main.clips[0].id) == [.position, .scale, .rotation, .opacity])
    #expect(base.keyableProperties(ofClip: base.tracks[1].clips[0].id) == [.volume])
    let arrow = Annotation(kind: .arrow(from: .zero, to: CGPoint(x: 50, y: 0)), color: RGBA(1, 0, 0), lineWidth: 4)
    let drawn = base.adding(annotation: arrow, at: 1)
    #expect(drawn.project.keyableProperties(ofClip: drawn.clip) == [.position, .scale, .rotation, .opacity, .reveal])
    let box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 0, y: 0, width: 20, height: 20)), color: RGBA(1, 0, 0), lineWidth: 4)
    let boxed = base.adding(annotation: box, at: 1)
    #expect(boxed.project.keyableProperties(ofClip: boxed.clip) == [.position, .scale, .rotation, .opacity])
    #expect(base.keyableProperties(ofClip: UUID()).isEmpty)
}

@Test func everyPropertyReadsAndWritesThroughOneAccessor() {
    var values = PropertyValues()
    var animation = ClipAnimation()
    for (index, property) in AnimatedProperty.allCases.enumerated() {
        let value: PropertyValue = property == .position ? .size(CGSize(width: index, height: 1)) : .number(Double(index) / 10)
        values[property] = value
        #expect(values[property] == value)
        animation.set(property, at: Double(index), to: values)
        #expect(animation.hasKeyframe(property, at: Double(index)))
        #expect(animation.values(at: Double(index), base: PropertyValues())[property] == value)
    }
    #expect(animation.times == AnimatedProperty.allCases.indices.map(Double.init))
    #expect(animation.removingKeyframes(at: 0).hasKeyframes(.position) == false)
    let (before, after) = animation.splitting(at: 2.5)
    #expect(before.times.last == 2.5)
    #expect(after.times.first == 0)
}
