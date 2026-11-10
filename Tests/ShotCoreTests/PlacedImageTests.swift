import CoreGraphics
import Testing
@testable import ShotCore

private func placed(cropped: Bool) -> Annotation {
    var a = Annotation(
        kind: .image(AnnotationImage(solidImage(width: 40, height: 20)), rect: CGRect(x: 0, y: 0, width: 40, height: 20)),
        color: RGBA(0, 0, 0), lineWidth: 0
    )
    if cropped {
        a.imageCrop = ImageCrop(left: 0.25, top: 0, right: 0, bottom: 0)
    }
    return a
}

// MARK: Soft shadow

@Test func aPlacedImageStartsWithTheSoftShadowInTheImageEditor() {
    let style = EditorStyle().editorObjectStyle(for: .image, scale: 2)
    #expect(style == ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 2)))
    #expect(StyleKind.image.editorDefaultStyle == ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1)))
}

@Test func onlyPlacedImagesStartWithAShadow() {
    for kind in [StyleKind.capture, .mark, .text] {
        #expect(EditorStyle().editorObjectStyle(for: kind, scale: 2).isEmpty)
        #expect(kind.editorDefaultStyle == kind.defaultStyle)
    }
}

@Test func aStyleGivenToAnImageWinsOverTheSoftShadow() {
    let plain = EditorStyle(objectStyles: [.image: ObjectStyle()])
    #expect(plain.editorObjectStyle(for: .image, scale: 2).isEmpty)
    let float = ObjectStyle(shadow: ShadowPreset.float.shadow(scale: 1))
    #expect(EditorStyle(objectStyles: [.image: float]).editorObjectStyle(for: .image, scale: 2) == float.scaled(by: 2))
}

@Test func theVideoEditorsImagesKeepThePlainDefault() {
    #expect(EditorStyle().objectStyle(for: .image, scale: 2).isEmpty)
    #expect(StyleKind.image.defaultStyle.isEmpty)
}

@Test func resetHasNothingToDoOnASoftShadowedImage() {
    let soft = ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 2))
    #expect(StyleKind.image.isEditorDefault(style: soft, cornerRadius: 0, scale: 2))
    #expect(!StyleKind.image.isEditorDefault(style: ObjectStyle(), cornerRadius: 0, scale: 2))
    #expect(!StyleKind.image.isEditorDefault(style: soft, cornerRadius: 8, scale: 2))
    #expect(StyleKind.mark.isEditorDefault(style: ObjectStyle(), cornerRadius: 0, scale: 2))
}

// MARK: Crop badge

@Test func theCropBadgeShowsOnACroppedImageWhileHoveredOrSelected() {
    let image = placed(cropped: true)
    #expect(CanvasCropBadge.shows(on: image, selected: true, hovered: false))
    #expect(CanvasCropBadge.shows(on: image, selected: false, hovered: true))
    #expect(!CanvasCropBadge.shows(on: image, selected: false, hovered: false))
}

@Test func theCropBadgeSkipsWholeLockedAndHiddenImages() {
    #expect(!CanvasCropBadge.shows(on: placed(cropped: false), selected: true, hovered: true))
    var locked = placed(cropped: true)
    locked.isLocked = true
    #expect(!CanvasCropBadge.shows(on: locked, selected: true, hovered: true))
    var hidden = placed(cropped: true)
    hidden.isHidden = true
    #expect(!CanvasCropBadge.shows(on: hidden, selected: true, hovered: true))
    let arrow = Annotation(kind: .arrow(from: .zero, to: CGPoint(x: 10, y: 10)), color: RGBA(0, 0, 0), lineWidth: 2)
    #expect(!CanvasCropBadge.shows(on: arrow, selected: true, hovered: true))
}

@Test func theCropBadgeSitsOnTheTopRightCornerOrPastItsHandle() {
    let rect = CGRect(x: 100.0, y: 50.0, width: 200.0, height: 120.0)
    #expect(CanvasCropBadge.center(of: rect, clearOfHandle: false) == CGPoint(x: 300.0, y: 50.0))
    #expect(CanvasCropBadge.center(of: rect, clearOfHandle: true) == CGPoint(x: 312.0, y: 38.0))
}

@Test func theCropBadgeStaysInsideTheCanvas() {
    let view = CGRect(x: 0.0, y: 0.0, width: 400.0, height: 300.0)
    // An image against the top right edge: the badge moves in until all of it shows.
    let center = CanvasCropBadge.center(of: CGRect(x: 200.0, y: 0.0, width: 200.0, height: 100.0), clearOfHandle: true, in: view)
    #expect(center == CGPoint(x: 391.0, y: 9.0))
    // With room around it, the view changes nothing.
    let free = CGRect(x: 100.0, y: 100.0, width: 100.0, height: 100.0)
    #expect(CanvasCropBadge.center(of: free, clearOfHandle: true, in: view) == CanvasCropBadge.center(of: free, clearOfHandle: true))
}

@Test func theCropBadgeClearsTheCornerHandle() {
    // The handle is 8 pt square on the corner; the moved badge's edge stays clear of it.
    let center = CanvasCropBadge.center(of: CGRect(x: 0.0, y: 100.0, width: 50.0, height: 50.0), clearOfHandle: true)
    let corner = CGPoint(x: 50.0, y: 100.0)
    let gap = hypot(center.x - corner.x, center.y - corner.y) - CanvasCropBadge.diameter / 2
    #expect(gap > 4.0 * 2.0.squareRoot())
    #expect(!CanvasCropBadge.contains(CGPoint(x: corner.x + 4, y: corner.y - 4), center: center))
}

@Test func aPressNearTheCropBadgeCounts() {
    let center = CGPoint(x: 10.0, y: 10.0)
    #expect(CanvasCropBadge.contains(center, center: center))
    #expect(CanvasCropBadge.contains(CGPoint(x: 20.0, y: 10.0), center: center))
    #expect(!CanvasCropBadge.contains(CGPoint(x: 22.0, y: 10.0), center: center))
}
