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

@Test func aNewClipIsAtItsDefaultsAndAChangedOneIsNot() throws {
    let (imported, id) = try withOverlay()
    #expect(imported.isAtDefaults(clip: id))
    var values = try #require(imported.values(ofClip: id, at: 3))
    values.rotation = 0.5
    let turned = try #require(imported.setting(values: values, ofClip: id, at: 3))
    #expect(!turned.isAtDefaults(clip: id))
    let keyed = try #require(imported.togglingKeyframe(.opacity, ofClip: id, at: 2))
    #expect(!keyed.isAtDefaults(clip: id), "keyframes count as a change")
    #expect(!imported.isAtDefaults(clip: UUID()))
}

@Test func resettingAClipClearsItsKeyframesAndPutsEverythingBack() throws {
    var (imported, id) = try withOverlay()
    imported = try #require(imported.togglingKeyframe(.scale, ofClip: id, at: 2))
    var values = try #require(imported.values(ofClip: id, at: 3))
    values.position = CGSize(width: 40, height: -10)
    values.rotation = 1
    values.opacity = 0.4
    values.volume = 0.2
    values.scale = 2
    imported = try #require(imported.setting(values: values, ofClip: id, at: 3))
    let cropped = try #require(imported.setting(crop: ImageCrop(left: 0.1, top: 0, right: 0, bottom: 0), of: id))
    let reset = try #require(cropped.resetting(clip: id))
    #expect(reset.isAtDefaults(clip: id))
    #expect(reset.clip(id)?.propertyValues == PropertyValues())
    #expect(reset.clip(id)?.animation.isEmpty == true)
    #expect(reset.clip(id)?.crop == cropped.clip(id)?.crop, "the crop stays")
}

@Test func resettingAnAnnotationClipPutsBackHowMuchIsDrawn() throws {
    let note = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 100, y: 100, width: 100, height: 60)), color: RGBA.presets[0], lineWidth: 4)
    let (withNote, id) = project().adding(annotation: note, at: 1)
    var values = try #require(withNote.values(ofClip: id, at: 2))
    values.reveal = 0.3
    values.scale = 1.5
    let changed = try #require(withNote.setting(values: values, ofClip: id, at: 2))
    #expect(!changed.isAtDefaults(clip: id))
    #expect(try #require(changed.resetting(clip: id)).isAtDefaults(clip: id))
}
