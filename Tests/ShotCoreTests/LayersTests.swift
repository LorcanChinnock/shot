import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let red = RGBA.presets[0]

private func annotation(_ kind: Annotation.Kind) -> Annotation {
    Annotation(kind: kind, color: red, lineWidth: 4)
}

private func solid(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
    let data = try #require(image.dataProvider?.data as Data?)
    let offset = y * image.bytesPerRow + x * 4
    return Array(data[offset..<offset + 4])
}

private struct Item: Identifiable, Equatable {
    let id: Int
}

private let items = (1...5).map(Item.init)
private func ids(_ items: [Item]) -> [Int] { items.map(\.id) }

@Test func movingOneStep() {
    #expect(ids(items.moving([2], .forward)) == [1, 3, 2, 4, 5])
    #expect(ids(items.moving([2], .backward)) == [2, 1, 3, 4, 5])
    #expect(ids(items.moving([5], .forward)) == [1, 2, 3, 4, 5])
    #expect(ids(items.moving([1], .backward)) == [1, 2, 3, 4, 5])
}

@Test func movingASelectionKeepsItsOrderAndStopsAtTheEnd() {
    #expect(ids(items.moving([2, 3], .forward)) == [1, 4, 2, 3, 5])
    #expect(ids(items.moving([4, 5], .forward)) == [1, 2, 3, 4, 5])
    #expect(ids(items.moving([2, 4], .backward)) == [2, 1, 4, 3, 5])
    #expect(ids(items.moving([1, 3], .toFront)) == [2, 4, 5, 1, 3])
    #expect(ids(items.moving([3, 5], .toBack)) == [3, 5, 1, 2, 4])
}

@Test func movingToAnIndexAmongTheRest() {
    #expect(ids(items.moving([1], toIndex: 4)) == [2, 3, 4, 5, 1])
    #expect(ids(items.moving([4, 5], toIndex: 1)) == [1, 4, 5, 2, 3])
    #expect(ids(items.moving([3], toIndex: 99)) == [1, 2, 4, 5, 3])
    #expect(ids(items.moving([3], toIndex: -4)) == [3, 1, 2, 4, 5])
}

@Test func namesComeFromTheKind() {
    #expect(annotation(.arrow(from: .zero, to: CGPoint(x: 1, y: 1))).layerName == "Arrow")
    #expect(annotation(.shape(.ellipse, rect: .zero)).layerName == "Ellipse")
    #expect(annotation(.text("  Click   here to\nsave the file now please ", origin: .zero, fontSize: 12)).layerName == "Click here to save the…")
    #expect(annotation(.text(" ", origin: .zero, fontSize: 12)).layerName == "Text")
    #expect(annotation(.counter(3, center: .zero)).layerName == "Step 3")
    #expect(annotation(.blur(.zero)).layerName == "Blur (image)")
    #expect(annotation(.spotlight(.zero, style: SpotlightStyle())).layerName == "Spotlight (image)")
}

@Test func hiddenAndLockedLayersCantBePickedOnTheCanvas() {
    var below = annotation(.shape(.rectangle, rect: CGRect(x: 0, y: 0, width: 100, height: 100)))
    below.fill = red
    var above = below
    above = above.withNewID()
    let layers = [below, above]
    #expect(layers.topmostIndex(at: CGPoint(x: 50, y: 50), tolerance: 2) == 1)
    var hidden = layers
    hidden[1].isHidden = true
    #expect(hidden.topmostIndex(at: CGPoint(x: 50, y: 50), tolerance: 2) == 0)
    hidden[0].isLocked = true
    #expect(hidden.topmostIndex(at: CGPoint(x: 50, y: 50), tolerance: 2) == nil)
}

@Test func hiddenAndLockedAreOptionalWhenDecoding() throws {
    let plain = annotation(.arrow(from: .zero, to: CGPoint(x: 1, y: 1)))
    let data = try JSONEncoder().encode(plain)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(!json.contains("hidden"))
    #expect(!json.contains("locked"))
    var flagged = plain
    flagged.isHidden = true
    flagged.isLocked = true
    let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(flagged))
    #expect(decoded.isHidden && decoded.isLocked)
}

@Test func aHiddenLayerIsNotDrawn() throws {
    let box = CGRect(x: 10, y: 10, width: 30, height: 30)
    var filled = annotation(.shape(.rectangle, rect: box))
    filled.fill = red
    var doc = EditorDocument(base: solid(width: 60, height: 60), annotations: [filled])
    #expect(try pixel(try #require(AnnotationRenderer.flatten(doc)), 25, 25) != [255, 255, 255, 255])
    doc.annotations[0].isHidden = true
    #expect(try pixel(try #require(AnnotationRenderer.flatten(doc)), 25, 25) == [255, 255, 255, 255])
}

@Test func aRedactionNeverCoversOrReadsAnotherAnnotation() throws {
    let box = CGRect(x: 10, y: 10, width: 30, height: 30)
    var filled = annotation(.shape(.rectangle, rect: box))
    filled.fill = red
    let redaction = annotation(.blur(CGRect(x: 0, y: 0, width: 60, height: 60)))
    let base = solid(width: 60, height: 60)
    let blurAbove = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: [filled, redaction])))
    let blurBelow = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: [redaction, filled])))
    #expect(try pixel(blurAbove, 25, 25) == pixel(blurBelow, 25, 25))
    #expect(try pixel(blurAbove, 25, 25) != [255, 255, 255, 255])
}

private func overlayProject() -> (project: Project, bottom: UUID, middle: UUID, top: UUID) {
    let source = URL(fileURLWithPath: "/tmp/a.mov")
    var project = Project(source: source, duration: 10, canvasSize: CGSize(width: 100, height: 100), hasAudio: false)
    let arrow = annotation(.arrow(from: .zero, to: CGPoint(x: 1, y: 1)))
    let first = project.adding(annotation: arrow, at: 0, duration: 5)
    project = first.project
    // Overlapping in time, so each lands on a track of its own.
    let second = project.adding(annotation: annotation(.blur(.zero)), at: 1, duration: 2)
    let third = second.project.adding(annotation: annotation(.counter(1, center: .zero)), at: 2, duration: 2)
    let overlays = third.project.overlayTracks
    return (third.project, overlays[0].id, overlays[1].id, overlays[2].id)
}

@Test func overlayTracksReorderWithinTheirOwnSlots() {
    let (project, bottom, middle, top) = overlayProject()
    #expect(project.overlayTracks.map(\.id) == [bottom, middle, top])
    let forward = project.movingOverlays([bottom], .forward)
    #expect(forward.overlayTracks.map(\.id) == [middle, bottom, top])
    #expect(forward.tracks[0].id == project.tracks[0].id)
    #expect(project.movingOverlays([top], .toBack).overlayTracks.map(\.id) == [top, bottom, middle])
    #expect(project.movingOverlays([bottom], toIndex: 2).overlayTracks.map(\.id) == [middle, top, bottom])
}

@Test func hidingOrLockingAnOverlayTrackLeavesTheOthers() {
    let (project, bottom, middle, _) = overlayProject()
    let hidden = project.setting(\.isHidden, to: true, ofOverlays: [middle])
    #expect(hidden.overlayTracks.map(\.isHidden) == [false, true, false])
    #expect(hidden.annotationClips(at: 2.5).count == 2)
    #expect(hidden.setting(\.isLocked, to: true, ofOverlays: [bottom]).overlayTracks.map(\.isLocked) == [true, false, false])
}

@Test func deletingOverlaysRemovesTheirTracks() {
    let (project, bottom, _, top) = overlayProject()
    #expect(project.deletingOverlays([bottom, top]).overlayTracks.count == 1)
    #expect(project.deletingOverlays([project.tracks[0].id]).tracks.count == project.tracks.count)
}

@Test func anOverlayTrackIsNamedByItsFirstClip() {
    let (project, bottom, _, _) = overlayProject()
    #expect(project.overlayTracks.first { $0.id == bottom }?.layerName == "Arrow")
    var shared = project.overlayTracks[0]
    shared.annotations.append(shared.annotations[0])
    #expect(shared.layerName == "Arrow +1")
}

@Test func aDropInTheFrontFirstListMapsToTheBackToFrontIndex() {
    // Listed top to bottom: 5 4 3 2 1. Drag the top row to just above the bottom one.
    let listed = Array(items.reversed())
    let moved: Set<Int> = [5]
    let index = LayerList.backToFrontIndex(movingOffsets: [0], toOffset: 4, count: 5)
    #expect(ids(items.moving(moved, toIndex: index)) == [1, 5, 2, 3, 4])
    #expect(listed.map(\.id) == [5, 4, 3, 2, 1])
    #expect(LayerList.backToFrontIndex(movingOffsets: [4], toOffset: 0, count: 5) == 4)
    #expect(LayerList.backToFrontIndex(movingOffsets: [1, 2], toOffset: 5, count: 5) == 0)
}
