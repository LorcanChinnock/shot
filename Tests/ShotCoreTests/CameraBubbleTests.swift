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
