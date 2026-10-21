import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private let red = RGBA.presets[0]
/// Twice as wide as tall, with its centre at (200, 150).
private let box = CGRect(x: 100, y: 100, width: 200, height: 100)

private func annotation(_ kind: Annotation.Kind) -> Annotation {
    Annotation(kind: kind, color: red, lineWidth: 4)
}

private func resized(_ kind: Annotation.Kind, _ handle: AnnotationHandle, to point: CGPoint, constrain: Bool = false, fromCenter: Bool = false) -> Annotation {
    var a = annotation(kind)
    a.resize(handle, to: point, constrain: constrain, fromCenter: fromCenter)
    return a
}

private func shape(_ handle: AnnotationHandle, to point: CGPoint, constrain: Bool = false, fromCenter: Bool = false) -> CGRect {
    resized(.shape(.rectangle, rect: box), handle, to: point, constrain: constrain, fromCenter: fromCenter).bounds
}

private func near(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
    abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
}

private func ends(_ a: Annotation) -> (from: CGPoint, to: CGPoint)? {
    switch a.kind {
    case let .arrow(from, to), let .line(from, to): (from, to)
    default: nil
    }
}

// MARK: Box corners

@Test func shiftOnACornerKeepsTheProportionsTheBoxStartedWith() {
    // Dragged further across: the width decides.
    #expect(shape(.bottomRight, to: CGPoint(x: 500, y: 220), constrain: true) == CGRect(x: 100, y: 100, width: 400, height: 200))
    // Dragged further down: the height decides.
    #expect(shape(.bottomRight, to: CGPoint(x: 250, y: 400), constrain: true) == CGRect(x: 100, y: 100, width: 600, height: 300))
    // The opposite corner stays put, whichever corner it is.
    // The opposite corner stays put, whichever corner it is: here both axes shrink by half.
    #expect(shape(.topLeft, to: CGPoint(x: 200, y: 150), constrain: true) == CGRect(x: 200, y: 150, width: 100, height: 50))
}

@Test func shiftOnACornerKeepsTheProportionsOfABoxThatWasNotDrawnWithShift() {
    let wide = CGRect(x: 0, y: 0, width: 300, height: 100)
    var a = annotation(.highlight(wide))
    a.resize(.bottomRight, to: CGPoint(x: 150, y: 90), constrain: true)
    #expect(a.bounds.width / a.bounds.height == 3)
}

@Test func optionOnACornerMirrorsTheDragAcrossTheCentre() {
    #expect(shape(.bottomRight, to: CGPoint(x: 350, y: 250), fromCenter: true) == CGRect(x: 50, y: 50, width: 300, height: 200))
    #expect(shape(.topLeft, to: CGPoint(x: 150, y: 120), fromCenter: true) == CGRect(x: 150, y: 120, width: 100, height: 60))
}

@Test func shiftAndOptionOnACornerKeepTheProportionsAroundTheCentre() {
    let result = shape(.bottomRight, to: CGPoint(x: 400, y: 200), constrain: true, fromCenter: true)
    #expect(result == CGRect(x: 0, y: 50, width: 400, height: 200))
    #expect(CGPoint(x: result.midX, y: result.midY) == CGPoint(x: 200, y: 150))
}

@Test func theModifiersStillFlipTheBoxPastTheOppositeSide() {
    // Shift: the anchor is the top-left corner, and the box keeps its 2:1 shape on the other side of it.
    #expect(shape(.bottomRight, to: CGPoint(x: 0, y: 60), constrain: true) == CGRect(x: 0, y: 50, width: 100, height: 50))
    // Option: dragged to the other side of the centre, the box flips around it.
    #expect(shape(.bottomRight, to: CGPoint(x: 150, y: 120), fromCenter: true) == CGRect(x: 150, y: 120, width: 100, height: 60))
    // Both: past the centre, in proportion.
    #expect(shape(.bottomRight, to: CGPoint(x: 100, y: 125), constrain: true, fromCenter: true) == CGRect(x: 100, y: 100, width: 200, height: 100))
}

// MARK: Box edges

@Test func shiftOnAnEdgeGrowsTheOtherAxisAroundItsCentre() {
    #expect(shape(.right, to: CGPoint(x: 400, y: 999), constrain: true) == CGRect(x: 100, y: 75, width: 300, height: 150))
    #expect(shape(.top, to: CGPoint(x: 999, y: 40), constrain: true) == CGRect(x: 40, y: 40, width: 320, height: 160))
    #expect(shape(.left, to: CGPoint(x: 150, y: 0), constrain: true) == CGRect(x: 150, y: 112.5, width: 150, height: 75))
}

@Test func optionOnAnEdgeMirrorsOnThatAxisOnly() {
    #expect(shape(.right, to: CGPoint(x: 350, y: 0), fromCenter: true) == CGRect(x: 50, y: 100, width: 300, height: 100))
    #expect(shape(.bottom, to: CGPoint(x: 0, y: 220), fromCenter: true) == CGRect(x: 100, y: 80, width: 200, height: 140))
}

@Test func shiftAndOptionOnAnEdgeMirrorAndKeepTheProportions() {
    #expect(shape(.right, to: CGPoint(x: 350, y: 0), constrain: true, fromCenter: true) == CGRect(x: 50, y: 75, width: 300, height: 150))
}

@Test func theModifiersStillFlipAnEdgePastTheOppositeSide() {
    #expect(shape(.right, to: CGPoint(x: 40, y: 0), constrain: true) == CGRect(x: 40, y: 135, width: 60, height: 30))
    #expect(shape(.right, to: CGPoint(x: 40, y: 0), fromCenter: true) == CGRect(x: 40, y: 100, width: 320, height: 100))
    #expect(shape(.right, to: CGPoint(x: 40, y: 0), constrain: true, fromCenter: true) == CGRect(x: 40, y: 70, width: 320, height: 160))
}

@Test(arguments: [
    Annotation.Kind.highlight(box), .pixelate(box), .blur(box), .spotlight(box, style: SpotlightStyle()), .shape(.ellipse, rect: box),
])
func everyBoxKindFollowsTheModifiers(kind: Annotation.Kind) {
    #expect(resized(kind, .bottomRight, to: CGPoint(x: 500, y: 220), constrain: true).bounds == CGRect(x: 100, y: 100, width: 400, height: 200))
    #expect(resized(kind, .bottomRight, to: CGPoint(x: 350, y: 250), fromCenter: true).bounds == CGRect(x: 50, y: 50, width: 300, height: 200))
}

@Test func aPenStrokeFollowsTheModifiersWithinItsBounds() {
    let stroke = [CGPoint(x: 20, y: 20), CGPoint(x: 50, y: 40), CGPoint(x: 80, y: 60)]
    var a = annotation(.freehand(stroke))
    a.resize(.bottomRight, to: CGPoint(x: 140, y: 140), constrain: true)
    // 60 × 40 grows by the larger factor, 120 / 40 = 3.
    #expect(a.bounds == CGRect(x: 20, y: 20, width: 180, height: 120))

    var b = annotation(.marker(stroke))
    b.resize(.bottomRight, to: CGPoint(x: 100, y: 80), fromCenter: true)
    // The box grows around its centre, (50, 40), to 100 × 80.
    #expect(b.bounds == CGRect(x: 0, y: 0, width: 100, height: 80))
}

@Test func aNoteIgnoresTheModifiers() {
    let plain = resized(.note("Hi", rect: box), .bottomRight, to: CGPoint(x: 400, y: 260))
    let modified = resized(.note("Hi", rect: box), .bottomRight, to: CGPoint(x: 400, y: 260), constrain: true, fromCenter: true)
    #expect(modified.bounds == plain.bounds)
}

@Test func withoutModifiersResizingIsUnchanged() {
    #expect(shape(.bottomRight, to: CGPoint(x: 140, y: 120)) == CGRect(x: 100, y: 100, width: 40, height: 20))
    #expect(shape(.right, to: CGPoint(x: 400, y: 999)) == CGRect(x: 100, y: 100, width: 300, height: 100))
}

// MARK: Lines and arrows

@Test(arguments: [true, false])
func shiftSnapsALineEndToFortyFiveDegreesAroundTheOtherEnd(arrow: Bool) {
    let kind: (CGPoint, CGPoint) -> Annotation.Kind = { arrow ? .arrow(from: $0, to: $1) : .line(from: $0, to: $1) }
    let flat = resized(kind(.zero, CGPoint(x: 100, y: 10)), .end, to: CGPoint(x: 100, y: 20), constrain: true)
    let length = hypot(CGFloat(100), CGFloat(20))
    #expect(near(ends(flat)!.to, CGPoint(x: length, y: 0)))
    #expect(ends(flat)!.from == .zero)

    // The start end snaps around the end that stays.
    let diagonal = resized(kind(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)), .start, to: CGPoint(x: 30, y: 40), constrain: true)
    let reach = hypot(CGFloat(70), CGFloat(40))
    #expect(near(ends(diagonal)!.from, CGPoint(x: 100 - reach * cos(.pi / 4), y: reach * sin(.pi / 4))))
    #expect(ends(diagonal)!.to == CGPoint(x: 100, y: 0))
}

@Test(arguments: [true, false])
func optionMovesBothEndsSymmetricallyAroundTheMidpoint(arrow: Bool) {
    let kind: (CGPoint, CGPoint) -> Annotation.Kind = { arrow ? .arrow(from: $0, to: $1) : .line(from: $0, to: $1) }
    let end = resized(kind(.zero, CGPoint(x: 100, y: 0)), .end, to: CGPoint(x: 80, y: 60), fromCenter: true)
    #expect(ends(end)! == (from: CGPoint(x: 20, y: -60), to: CGPoint(x: 80, y: 60)))
    let start = resized(kind(.zero, CGPoint(x: 100, y: 0)), .start, to: CGPoint(x: -20, y: 30), fromCenter: true)
    #expect(ends(start)! == (from: CGPoint(x: -20, y: 30), to: CGPoint(x: 120, y: -30)))
}

@Test func shiftAndOptionSnapAroundTheMidpointAndMirror() {
    let a = resized(.line(from: .zero, to: CGPoint(x: 100, y: 0)), .end, to: CGPoint(x: 80, y: 10), constrain: true, fromCenter: true)
    let reach = hypot(CGFloat(30), CGFloat(10))
    #expect(near(ends(a)!.to, CGPoint(x: 50 + reach, y: 0)))
    #expect(near(ends(a)!.from, CGPoint(x: 50 - reach, y: 0)))
}

@Test func dragAnEndAcrossTheOtherWithTheModifiers() {
    // Past the other end, the snapped end carries on the far side.
    let a = resized(.arrow(from: .zero, to: CGPoint(x: 100, y: 0)), .end, to: CGPoint(x: -50, y: -4), constrain: true)
    #expect(near(ends(a)!.to, CGPoint(x: -hypot(CGFloat(50), CGFloat(4)), y: 0)))
    let b = resized(.arrow(from: .zero, to: CGPoint(x: 100, y: 0)), .end, to: CGPoint(x: 10, y: 0), fromCenter: true)
    #expect(ends(b)! == (from: CGPoint(x: 90, y: 0), to: CGPoint(x: 10, y: 0)))
}

@Test func theMiddleHandleIgnoresTheModifiers() {
    let plain = resized(.arrow(from: .zero, to: CGPoint(x: 100, y: 0)), .mid, to: CGPoint(x: 50, y: 30))
    let modified = resized(.arrow(from: .zero, to: CGPoint(x: 100, y: 0)), .mid, to: CGPoint(x: 50, y: 30), constrain: true, fromCenter: true)
    #expect(modified.kind == plain.kind && modified.bend == plain.bend)
}

// MARK: Images

private func placed(_ rect: CGRect) -> Annotation {
    Annotation(kind: .image(AnnotationImage(solidImage(width: 200, height: 100)), rect: rect), color: red, lineWidth: 0)
}

@Test func anImageKeepsItsProportionsWithoutShiftAndResizesFreelyWithIt() {
    var kept = placed(box)
    kept.resize(.bottomRight, to: CGPoint(x: 500, y: 150))
    #expect(kept.bounds == CGRect(x: 100, y: 100, width: 400, height: 200))

    var free = placed(box)
    free.resize(.bottomRight, to: CGPoint(x: 500, y: 150), constrain: true)
    #expect(free.bounds == CGRect(x: 100, y: 100, width: 400, height: 50))

    var corner = placed(box)
    corner.resize(.topLeft, to: CGPoint(x: 250, y: 20), constrain: true)
    #expect(corner.bounds == CGRect(x: 250, y: 20, width: 50, height: 180))
}

@Test func optionResizesAnImageFromItsCentreKeepingItsProportions() {
    var a = placed(box)
    a.resize(.bottomRight, to: CGPoint(x: 400, y: 250), fromCenter: true)
    #expect(a.bounds == CGRect(x: 0, y: 50, width: 400, height: 200))

    var b = placed(box)
    b.resize(.topLeft, to: CGPoint(x: 150, y: 125), fromCenter: true)
    #expect(b.bounds == CGRect(x: 150, y: 125, width: 100, height: 50))
}

@Test func shiftAndOptionResizeAnImageFreelyFromItsCentre() {
    var a = placed(box)
    a.resize(.bottomRight, to: CGPoint(x: 400, y: 200), constrain: true, fromCenter: true)
    #expect(a.bounds == CGRect(x: 0, y: 100, width: 400, height: 100))
}

@Test func anImageNeverFlipsOrVanishesWithTheModifiers() {
    for (constrain, fromCenter) in [(true, false), (false, true), (true, true)] {
        var a = placed(box)
        a.resize(.bottomRight, to: CGPoint(x: 0, y: 0), constrain: constrain, fromCenter: fromCenter)
        #expect(a.bounds.width >= AnnotationImage.minSide && a.bounds.height >= AnnotationImage.minSide)
        if !constrain {
            #expect(abs(a.bounds.width / a.bounds.height - 2) < 0.001)
        }
    }
    var edge = placed(box)
    edge.resize(.right, to: CGPoint(x: 600, y: 150), constrain: true, fromCenter: true)
    #expect(edge.bounds == box)
}
