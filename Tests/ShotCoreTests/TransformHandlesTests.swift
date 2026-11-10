import CoreGraphics
import Testing
@testable import ShotCore

private let video = CGSize(width: 640, height: 360)
private let inset = CGSize(width: 64, height: 20)

@Test func transformRotateHandleSitsAboveASmallClip() {
    // A 200 pt tall clip in the middle: its top edge is 100 pt above the centre, and the handle 22 pt above that.
    let handle = TransformHandles.rotateHandle(center: CGPoint(x: 320, y: 180), topMiddle: CGVector(dx: 0, dy: -100), rotation: 0, video: video, inset: inset)
    #expect(!handle.flipped)
    #expect(handle.point == CGPoint(x: 320, y: 58))
}

@Test func transformRotateHandleStepsInsideAClipFillingTheFrame() {
    // Above the top edge would be 22 pt above the video, past the well's 20 pt.
    let handle = TransformHandles.rotateHandle(center: CGPoint(x: 320, y: 180), topMiddle: CGVector(dx: 0, dy: -180), rotation: 0, video: video, inset: inset)
    #expect(handle.flipped)
    #expect(handle.point == CGPoint(x: 320, y: 22))
}

@Test func transformRotateHandleTurnsWithTheClip() {
    // Turned a quarter clockwise, the top edge faces right, so the handle sits right of the clip.
    let handle = TransformHandles.rotateHandle(center: CGPoint(x: 320, y: 180), topMiddle: CGVector(dx: 0, dy: -50), rotation: .pi / 2, video: video, inset: inset)
    #expect(!handle.flipped)
    #expect(abs(handle.point.x - 392) < 0.001 && abs(handle.point.y - 180) < 0.001)
}
