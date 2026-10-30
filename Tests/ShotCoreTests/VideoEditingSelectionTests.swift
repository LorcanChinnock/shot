import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let canvas = CGSize(width: 640, height: 360)
private let overlay = ImportedMedia(source: URL(fileURLWithPath: "/tmp/overlay.mov"), duration: 4, size: CGSize(width: 64, height: 36), hasAudio: true)

private func project() -> Project {
    Project(source: URL(fileURLWithPath: "/tmp/recording.mov"), duration: 10, canvasSize: canvas, hasAudio: true)
}

private func withOverlay() throws -> (project: Project, id: UUID) {
    let (imported, id) = try #require(project().importing(overlay, at: 2))
    return (imported, id)
}

@Test func theFrameCropIsTakenOffWhileItIsAdjusted() {
    let cropped = project().setting(frameCrop: CGRect(x: 0, y: 0, width: 320, height: 180))
    #expect(cropped.frameCrop != nil)
    #expect(cropped.showing(cropping: .frame).frameCrop == nil)
    #expect(cropped.showing(cropping: nil) == cropped)
}

@Test func aClipCropIsTakenOffWhileItIsAdjusted() throws {
    let (imported, id) = try withOverlay()
    let visible = CGRect(x: 0, y: 0, width: 32, height: 18)
    let cropped = try #require(imported.applying(cropDraft: visible, bounds: CGRect(x: 0, y: 0, width: 64, height: 36), to: .clip(id)))
    #expect(cropped.clip(id)?.crop != nil)
    #expect(cropped.showing(cropping: .clip(id)).clip(id)?.crop == nil)
}

@Test func showingACropOfAClipThatIsGoneChangesNothing() {
    let original = project()
    #expect(original.showing(cropping: .clip(UUID())) == original)
}

@Test func theFrameCropReachesTheCanvasAndAClipCropItsWholePicture() throws {
    let (imported, id) = try withOverlay()
    #expect(imported.cropBounds(of: .frame) == CGRect(origin: .zero, size: canvas))
    #expect(imported.cropBounds(of: .clip(id)) == CGRect(x: 0, y: 0, width: 64, height: 36))
    #expect(imported.cropBounds(of: .clip(UUID())) == nil)
    #expect(imported.cropBounds(of: nil) == nil)
}

@Test func applyingAFrameCropSetsIt() {
    let draft = CGRect(x: 10, y: 10, width: 320, height: 180)
    let changed = project().applying(cropDraft: draft, bounds: CGRect(origin: .zero, size: canvas), to: .frame)
    #expect(changed?.frameCrop == draft)
}

@Test func applyingACropToAClipThatIsGoneReturnsNil() {
    #expect(project().applying(cropDraft: CGRect(x: 0, y: 0, width: 10, height: 10), bounds: CGRect(x: 0, y: 0, width: 20, height: 20), to: .clip(UUID())) == nil)
}

@Test func aRestoredProjectKeepsTheClipItStillHas() throws {
    let (imported, id) = try withOverlay()
    let kept = imported.keepingSelection(clip: id, keyframe: nil)
    #expect(kept.clip == id)
}

@Test func aRestoredProjectDropsAClipItDoesNotHave() throws {
    let (_, id) = try withOverlay()
    let kept = project().keepingSelection(clip: id, keyframe: 1)
    #expect(kept.clip == nil)
    #expect(kept.keyframe == nil)
}

@Test func nothingSelectedStaysNothing() {
    let kept = project().keepingSelection(clip: nil, keyframe: nil)
    #expect(kept.clip == nil)
    #expect(kept.keyframe == nil)
}

@Test func aRestoredProjectKeepsAKeyframeItStillHasAndDropsOneItDoesNot() throws {
    var (imported, id) = try withOverlay()
    imported = try #require(imported.togglingKeyframe(.scale, ofClip: id, at: 2))
    let keyframe = try #require(imported.animation(ofClip: id)?.scale.first?.time)
    #expect(imported.keepingSelection(clip: id, keyframe: keyframe).keyframe == keyframe)
    #expect(imported.keepingSelection(clip: id, keyframe: keyframe + 1).keyframe == nil)
}

@Test func aSelectionIsTheRangeBetweenTwoTimesWhicheverComesFirst() {
    let forward = TimelineSelection.range(from: 2, to: 5, duration: 10)
    #expect(forward.range == 2..<5)
    #expect(forward.shownTime == 5)
    let backward = TimelineSelection.range(from: 5, to: 2, duration: 10)
    #expect(backward.range == 2..<5)
    #expect(backward.shownTime == 2)
}

@Test func aSelectionStaysWithinTheTimeline() {
    let selection = TimelineSelection.range(from: -3, to: 14, duration: 10)
    #expect(selection.range == 0..<10)
    #expect(selection.shownTime == 10)
}

@Test func twoTimesThatMeetSelectNothingButStillShowTheTime() {
    let selection = TimelineSelection.range(from: 4, to: 4, duration: 10)
    #expect(selection.range == nil)
    #expect(selection.shownTime == 4)
    #expect(TimelineSelection.range(from: 12, to: 20, duration: 10).range == nil)
}

private func box() -> Annotation {
    Annotation(kind: .shape(.rectangle, rect: CGRect(x: 100, y: 100, width: 100, height: 60)), color: RGBA.presets[0], lineWidth: 4)
}

@Test func aRestoredProjectKeepsAnAnnotationClipItStillHas() {
    let (annotated, id) = project().adding(annotation: box(), at: 2)
    #expect(annotated.keepingSelection(clip: id, keyframe: nil).clip == id)
}

@Test func aRestoredProjectDropsAnAnnotationClipItDoesNotHave() {
    let (_, id) = project().adding(annotation: box(), at: 2)
    #expect(project().keepingSelection(clip: id, keyframe: nil).clip == nil)
}

@Test func aRestoredProjectKeepsAnAnnotationClipsKeyframe() throws {
    var (annotated, id) = project().adding(annotation: box(), at: 2)
    annotated = try #require(annotated.togglingKeyframe(.scale, ofClip: id, at: 3))
    let keyframe = try #require(annotated.animation(ofClip: id)?.scale.first?.time)
    #expect(annotated.keepingSelection(clip: id, keyframe: keyframe).keyframe == keyframe)
}
