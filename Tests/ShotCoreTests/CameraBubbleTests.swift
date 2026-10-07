import CoreGraphics
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
