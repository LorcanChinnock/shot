import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

@Test func bubbleStartsInsideRegionBottomLeft() {
    let region = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
    let frame = CameraBubbleLayout.initialFrame(in: region, diameter: 220, inset: 24)
    #expect(frame == CGRect(x: -1896, y: -156, width: 220, height: 220))
    #expect(region.contains(frame))
}

@Test func resizeKeepsCenter() {
    let frame = CGRect(x: 100, y: 100, width: 220, height: 220)
    let resized = CameraBubbleLayout.resized(frame, to: 300)
    #expect(resized.midX == frame.midX)
    #expect(resized.midY == frame.midY)
    #expect(resized.width == 300)
}

@Test func sizeCyclesAndFitsSmallRegions() {
    #expect(CameraBubbleSize.small.next == .medium)
    #expect(CameraBubbleSize.large.next == .small)
    let region = CGRect(x: 0, y: 0, width: 800, height: 250)
    #expect(CameraBubbleSize.fitting(.large, in: region, inset: 24) == .small)
    #expect(CameraBubbleSize.fitting(.medium, in: CGRect(x: 0, y: 0, width: 2000, height: 1000), inset: 24) == .medium)
    #expect(CameraBubbleSize.fitting(.small, in: CGRect(x: 0, y: 0, width: 100, height: 100), inset: 24) == nil)
}

@Test func clampKeepsBubbleInsideRegion() {
    let region = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
    let inside = CGRect(x: -1000, y: 200, width: 220, height: 220)
    #expect(CameraBubbleLayout.clamped(inside, in: region, inset: 24) == inside)
    let pastTopRight = CGRect(x: 100, y: 1000, width: 220, height: 220)
    #expect(CameraBubbleLayout.clamped(pastTopRight, in: region, inset: 24) == CGRect(x: -244, y: 656, width: 220, height: 220))
    let pastBottomLeft = CGRect(x: -3000, y: -500, width: 220, height: 220)
    #expect(CameraBubbleLayout.clamped(pastBottomLeft, in: region, inset: 24) == CGRect(x: -1896, y: -156, width: 220, height: 220))
}

@Test func clampFavoursBottomLeftWhenBubbleCannotFit() {
    let region = CGRect(x: 0, y: 0, width: 200, height: 200)
    let frame = CGRect(x: 50, y: 50, width: 300, height: 300)
    #expect(CameraBubbleLayout.clamped(frame, in: region, inset: 24).origin == CGPoint(x: 24, y: 24))
}

@Test func sizeStepsStopAtTheEnds() {
    #expect(CameraBubbleSize.small.stepped(by: 1) == .medium)
    #expect(CameraBubbleSize.large.stepped(by: -1) == .medium)
    #expect(CameraBubbleSize.large.stepped(by: 1) == nil)
    #expect(CameraBubbleSize.small.stepped(by: -1) == nil)
}

@Test func nearestSizeSnapsToSettingsSizes() {
    #expect(CameraBubbleSize.nearest(toDiameter: 0) == .small)
    #expect(CameraBubbleSize.nearest(toDiameter: 185) == .small)
    #expect(CameraBubbleSize.nearest(toDiameter: 200) == .medium)
    #expect(CameraBubbleSize.nearest(toDiameter: 270) == .large)
    #expect(CameraBubbleSize.nearest(toDiameter: 900) == .large)
}

@Test func bubbleStartsEighteenPointsIn() {
    let region = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let frame = CameraBubbleLayout.initialFrame(in: region, diameter: 160, inset: CameraBubbleStyle.inset)
    #expect(frame.origin == CGPoint(x: 18, y: 18))
    #expect(CameraBubbleStyle.margin == 4)
}

@Test func handleFacesTheMiddleOfTheArea() {
    let region = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let left = CGRect(x: 18, y: 18, width: 160, height: 160)
    let offset = 80 / 2.0.squareRoot()
    let onLeft = CameraBubbleLayout.handleCenter(for: left, in: region)
    #expect(abs(onLeft.x - (98 + offset)) < 0.001)
    #expect(abs(onLeft.y - (98 - offset)) < 0.001)
    let right = CGRect(x: 822, y: 18, width: 160, height: 160)
    let onRight = CameraBubbleLayout.handleCenter(for: right, in: region)
    #expect(abs(onRight.x - (902 - offset)) < 0.001)
    // On the circle's edge, inside its square, so the window needs no room for it.
    #expect(abs(hypot(onLeft.x - left.midX, onLeft.y - left.midY) - 80) < 0.001)
    #expect(left.insetBy(dx: CameraBubbleStyle.handleDiameter / 2, dy: CameraBubbleStyle.handleDiameter / 2).contains(onLeft))
}

@Test func handleDragSnapsAndFits() {
    let region = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let circle = CGRect(x: 100, y: 100, width: 220, height: 220)
    let center = CGPoint(x: circle.midX, y: circle.midY)
    #expect(CameraBubbleLayout.resizeTarget(pointer: CGPoint(x: center.x + 150, y: center.y), circle: circle, region: region, inset: 18) == .large)
    #expect(CameraBubbleLayout.resizeTarget(pointer: CGPoint(x: center.x, y: center.y - 70), circle: circle, region: region, inset: 18) == .small)
    let short = CGRect(x: 0, y: 0, width: 1000, height: 230)
    #expect(CameraBubbleLayout.resizeTarget(pointer: CGPoint(x: center.x + 150, y: center.y), circle: circle, region: short, inset: 18) == .small)
    #expect(CameraBubbleLayout.resizeTarget(pointer: center, circle: circle, region: CGRect(x: 0, y: 0, width: 150, height: 150), inset: 18) == nil)
}
