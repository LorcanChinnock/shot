import CoreGraphics
import CoreImage
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
    #expect(annotation(.blur(.zero)).layerName == "Blur")
    #expect(annotation(.spotlight(.zero, style: SpotlightStyle())).layerName == "Spotlight")
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

private func effect(_ name: String) -> Annotation {
    switch name {
    case "spotlight": annotation(.spotlight(CGRect(x: 48, y: 48, width: 10, height: 10), style: SpotlightStyle()))
    case "blur": annotation(.blur(CGRect(x: 0, y: 0, width: 60, height: 60)))
    default: annotation(.pixelate(CGRect(x: 0, y: 0, width: 60, height: 60)))
    }
}

/// A filled square on white, with its left edge on an odd pixel, so a blur or pixelate over it mixes in the white.
private func square() -> Annotation {
    var square = annotation(.shape(.rectangle, rect: CGRect(x: 13, y: 13, width: 30, height: 30)))
    square.fill = red
    return square
}

/// The pixels where `square()` is drawn.
private func square(of image: CGImage) throws -> [[UInt8]] {
    try stride(from: 13, to: 43, by: 1).flatMap { y in try stride(from: 13, to: 43, by: 1).map { x in try pixel(image, x, y) } }
}

@Test(arguments: ["spotlight", "blur", "pixelate"])
func anEffectActsOnTheLayersUnderItAndNotThoseOverIt(_ name: String) throws {
    let base = solid(width: 60, height: 60)
    let plain = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: [square()])))
    let over = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: [square(), effect(name)])))
    let under = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: [effect(name), square()])))
    #expect(try square(of: over) != square(of: plain))
    #expect(try square(of: under) == square(of: plain))
}

@Test(arguments: ["spotlight", "blur", "pixelate"])
func aHiddenLayerIsLeftOutOfTheEffectOverIt(_ name: String) throws {
    let base = solid(width: 60, height: 60)
    var hidden = square()
    hidden.isHidden = true
    let flat = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: [hidden, effect(name)])))
    let alone = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: [effect(name)])))
    #expect(try square(of: flat) == square(of: alone))
}

@Test func aRedactionOverAnotherCoversItsResult() throws {
    // A pixelate over a blur pixelates the blurred square, not the sharp one.
    let base = solid(width: 60, height: 60)
    let blur = annotation(.blur(CGRect(x: 0, y: 0, width: 30, height: 60)))
    let pixelate = annotation(.pixelate(CGRect(x: 0, y: 0, width: 60, height: 60)))
    let stacked = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: [square(), blur, pixelate])))
    let sharp = try #require(AnnotationRenderer.flatten(EditorDocument(base: base, annotations: [square(), pixelate])))
    #expect(try square(of: stacked) != square(of: sharp))
}

@Test func videoOverlaysActOnTheTracksUnderThem() throws {
    let canvas = CGRect(x: 0, y: 0, width: 60, height: 60)
    let context = CIContext()
    func frame(_ annotations: [Annotation]) throws -> CGImage {
        let white = CIImage(color: .white).cropped(to: canvas)
        let image = AnnotationFrame.apply(annotations.map { AnnotationFrame.Item(annotation: $0) }, to: white, canvas: canvas, context: context)
        return try #require(context.createCGImage(image, from: canvas, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
    }
    let plain = try frame([square()])
    #expect(try pixel(try frame([square(), effect("spotlight")]), 28, 28) != pixel(plain, 28, 28))
    #expect(try pixel(try frame([effect("spotlight"), square()]), 28, 28) == pixel(plain, 28, 28))
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

/// The annotations on each overlay track, bottom first.
private func lanes(_ project: Project) -> [[UUID]] {
    project.overlayTracks.map { $0.annotations.map(\.id) }
}

private func clip(on track: UUID, of project: Project) -> UUID {
    project.tracks.first { $0.id == track }!.annotations[0].id
}

@Test func aClipDroppedOnAFreeLaneMovesThereAndKeepsItsTime() throws {
    let (project, bottom, _, top) = overlayProject()
    let added = project.adding(annotation: annotation(.counter(2, center: .zero)), at: 6, duration: 2)
    #expect(added.project.trackID(ofAnnotation: added.clip) == bottom)
    let topIndex = try #require(added.project.tracks.firstIndex { $0.id == top })
    let moved = try #require(added.project.movingAnnotation(added.clip, toStart: 6.5, onto: .onto(topIndex)))
    #expect(moved.trackID(ofAnnotation: added.clip) == top)
    #expect(moved.annotationClip(added.clip)?.start == 6.5)
    #expect(moved.overlayTracks.count == 3)
}

@Test func aClipDroppedOnATakenLaneGetsANewOneAboveIt() throws {
    let (project, bottom, middle, top) = overlayProject()
    let arrow = clip(on: bottom, of: project)
    let topIndex = try #require(project.tracks.firstIndex { $0.id == top })
    let moved = try #require(project.movingAnnotation(arrow, toStart: 0, onto: .onto(topIndex)))
    // The arrow's own track emptied, so it went.
    #expect(lanes(moved) == [[clip(on: middle, of: project)], [clip(on: top, of: project)], [arrow]])
}

@Test func aClipDroppedBetweenLanesGetsANewTrackThere() throws {
    let (project, bottom, middle, top) = overlayProject()
    let blur = clip(on: middle, of: project)
    let bottomIndex = try #require(project.tracks.firstIndex { $0.id == bottom })
    let moved = try #require(project.movingAnnotation(blur, toStart: 1, onto: .insert(bottomIndex)))
    #expect(lanes(moved) == [[blur], [clip(on: bottom, of: project)], [clip(on: top, of: project)]])
}

@Test func aLoneClipDroppedNextToItsOwnLaneStaysOnIt() throws {
    var (project, _, middle, _) = overlayProject()
    let middleIndex = try #require(project.tracks.firstIndex { $0.id == middle })
    project.tracks[middleIndex].isHidden = true
    let blur = clip(on: middle, of: project)
    for drop in [LaneDrop.insert(middleIndex), .insert(middleIndex + 1)] {
        let moved = try #require(project.movingAnnotation(blur, toStart: 1.5, onto: drop))
        #expect(moved.trackID(ofAnnotation: blur) == middle)
        #expect(moved.tracks[middleIndex].isHidden)
        #expect(moved.annotationClip(blur)?.start == 1.5)
    }
}

@Test func theKeyboardMovesAClipALaneAtATime() throws {
    let (project, bottom, middle, top) = overlayProject()
    let arrow = clip(on: bottom, of: project), blur = clip(on: middle, of: project), counter = clip(on: top, of: project)
    // The blur's lane is taken where the arrow is, so it gets a new lane just above it.
    let forward = try #require(project.movingAnnotation(arrow, .forward))
    #expect(lanes(forward) == [[blur], [arrow], [counter]])
    let toBack = try #require(project.movingAnnotation(counter, .toBack))
    #expect(lanes(toBack) == [[arrow], [counter], [blur]])
    // Already alone at the top or bottom, it stays.
    #expect(project.movingAnnotation(counter, .forward) == nil)
    #expect(project.movingAnnotation(arrow, .toBack) == nil)
}

@Test func whereADraggedClipLandsDependsOnHowNearALaneEdgeItIs() {
    let (project, _, _, _) = overlayProject()
    // Lanes top down: the top track (3) at 0–28, the middle (2) at 32–60, the bottom (1) at 64–92, then the main track.
    let layout = LaneLayout(project, top: 0)
    #expect(layout.laneDrop(at: 2, in: project) == .insert(4))
    #expect(layout.laneDrop(at: 14, in: project) == .onto(3))
    #expect(layout.laneDrop(at: 27, in: project) == .insert(3))
    #expect(layout.laneDrop(at: 46, in: project) == .onto(2))
    #expect(layout.laneDrop(at: 90, in: project) == .insert(1))
    #expect(layout.laneDrop(at: 120, in: project) == .insert(1))
}

@Test func deletingOverlaysRemovesTheirTracks() {
    let (project, bottom, _, top) = overlayProject()
    #expect(project.deletingOverlays([bottom, top]).overlayTracks.count == 1)
    #expect(project.deletingOverlays([project.tracks[0].id]).tracks.count == project.tracks.count)
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

/// Drags `moving` in the frontmost-first list of `items` into the gap before the `gap`th row that stays, as the panel does.
private func drop(_ moving: Set<Int>, gap: Int) -> [Int]? {
    let listed = items.reversed().map(\.id)
    guard let destination = LayerList.destination(of: listed, moving: moving, gap: gap) else {
        return nil
    }
    let offsets = IndexSet(listed.indices.filter { moving.contains(listed[$0]) })
    return ids(items.moving(moving, toIndex: LayerList.backToFrontIndex(movingOffsets: offsets, toOffset: destination, count: listed.count)))
}

@Test func draggingARowPutsItInTheGapItWasDroppedIn() {
    // Listed top to bottom: 5 4 3 2 1.
    #expect(drop([5], gap: 4) == [5, 1, 2, 3, 4])
    #expect(drop([5], gap: 3) == [1, 5, 2, 3, 4])
    #expect(drop([1], gap: 0) == [2, 3, 4, 5, 1])
    #expect(drop([3], gap: 1) == [1, 2, 4, 3, 5])
    // Dropped back where it started, nothing moves.
    #expect(drop([3], gap: 2) == nil)
    // A selection moves together, keeping its order.
    #expect(drop([5, 3], gap: 3) == [3, 5, 1, 2, 4])
    #expect(drop([4, 2], gap: 0) == [1, 3, 5, 2, 4])
}

private func layered() -> (doc: EditorDocument, bottom: UUID, middle: UUID, top: UUID) {
    var middle = annotation(.counter(1, center: CGPoint(x: 30, y: 30)))
    middle.isLocked = true
    let doc = EditorDocument(base: solid(width: 60, height: 60), annotations: [annotation(.arrow(from: .zero, to: CGPoint(x: 9, y: 9))), middle, annotation(.blur(CGRect(x: 0, y: 0, width: 9, height: 9)))])
    return (doc, doc.annotations[0].id, middle.id, doc.annotations[2].id)
}

@Test func deletingLayersSkipsLockedOnesAndUndoesInOneStep() {
    var (doc, bottom, middle, top) = layered()
    var undo = UndoStack<EditorSnapshot>()
    let before = doc.snapshot
    undo.record(before)
    #expect(doc.deleteLayers([bottom, middle, top], margin: 16) == [bottom, top])
    #expect(doc.annotations.map(\.id) == [middle])
    doc.restore(undo.undo(from: doc.snapshot)!)
    #expect(doc.snapshot == before)
    #expect(!undo.canUndo)
}

@Test func deletingOnlyLockedLayersChangesNothing() {
    var (doc, _, middle, _) = layered()
    let before = doc.snapshot
    #expect(doc.deleteLayers([middle], margin: 16).isEmpty)
    #expect(doc.snapshot == before)
}

@Test func deletingALayerInThePaddingPullsTheCanvasBackIn() {
    var doc = EditorDocument(base: solid(width: 60, height: 60))
    let past = annotation(.shape(.rectangle, rect: CGRect(x: 70, y: 10, width: 20, height: 20)))
    doc.annotations.append(past)
    doc.grow(toFit: past, margin: 16)
    #expect(doc.canvasRect.maxX > 60)
    doc.deleteLayers([past.id], margin: 16)
    #expect(doc.canvasRect == doc.fullRect)
}
