import CoreGraphics
import Testing
@testable import ShotCore

@Test func flipOnPrimaryDisplay() {
    let appKit = CGRect(x: 100, y: 700, width: 200, height: 100)
    let cg = Geometry.flip(appKit, primaryHeight: 900)
    #expect(cg == CGRect(x: 100, y: 100, width: 200, height: 100))
    #expect(Geometry.flip(cg, primaryHeight: 900) == appKit)
}

@Test func flipOnSecondaryDisplayAtNegativeOffset() {
    // Secondary 1920 × 1080 display left of a 1440 × 900 primary, bottom edge 180 pt lower.
    let secondary = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
    #expect(Geometry.flip(secondary, primaryHeight: 900) == CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    let rect = CGRect(x: -1800, y: -100, width: 200, height: 50)
    #expect(Geometry.flip(rect, primaryHeight: 900) == CGRect(x: -1800, y: 950, width: 200, height: 50))
    #expect(Geometry.displayLocalTopLeft(rect, screenFrame: secondary) == CGRect(x: 120, y: 950, width: 200, height: 50))
}

@Test func normalizedFromAnyDirection() {
    let expected = CGRect(x: 10, y: 20, width: 30, height: 40)
    let a = CGPoint(x: 10, y: 20), b = CGPoint(x: 40, y: 60)
    #expect(Geometry.normalized(from: a, to: b) == expected)
    #expect(Geometry.normalized(from: b, to: a) == expected)
    #expect(Geometry.normalized(from: CGPoint(x: 10, y: 60), to: CGPoint(x: 40, y: 20)) == expected)
}

@Test func squareConstraint() {
    #expect(Geometry.square(from: .zero, to: CGPoint(x: 50, y: 30)) == CGRect(x: 0, y: 0, width: 30, height: 30))
    #expect(Geometry.square(from: .zero, to: CGPoint(x: -20, y: 70)) == CGRect(x: -20, y: 0, width: 20, height: 20))
}

@Test(arguments: [1.0, 2.0])
func cropRectConversion(scale: CGFloat) {
    let rect = Geometry.pixelRect(forViewRect: CGRect(x: 10, y: 700, width: 100, height: 50), viewHeight: 900, scale: scale)
    #expect(rect == CGRect(x: 10 * scale, y: 150 * scale, width: 100 * scale, height: 50 * scale))
}

@Test func evenFloor() {
    #expect(Geometry.evenFloor(1001.7) == 1000)
    #expect(Geometry.evenFloor(1000) == 1000)
}

@Test func windowHitTestPrefersFrontmost() {
    let front = WindowInfo(windowID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), ownerPID: 10)
    let back = WindowInfo(windowID: 2, frame: CGRect(x: 0, y: 0, width: 300, height: 300), ownerPID: 11)
    #expect(WindowInfo.topmost(at: CGPoint(x: 50, y: 50), in: [front, back]) == front)
    #expect(WindowInfo.topmost(at: CGPoint(x: 200, y: 200), in: [front, back]) == back)
    #expect(WindowInfo.topmost(at: CGPoint(x: 500, y: 500), in: [front, back]) == nil)
}

@Test func windowParsingFiltersLayerOwnerAndSize() {
    func entry(_ id: Int, layer: Int, pid: Int, size: CGFloat) -> [String: Any] {
        [
            kCGWindowNumber as String: id, kCGWindowLayer as String: layer, kCGWindowOwnerPID as String: pid,
            kCGWindowBounds as String: CGRect(x: 0, y: 0, width: size, height: size).dictionaryRepresentation,
        ]
    }
    let parsed = WindowInfo.parse([entry(1, layer: 0, pid: 5, size: 100), entry(2, layer: 25, pid: 5, size: 100), entry(3, layer: 0, pid: 99, size: 100), entry(4, layer: 0, pid: 5, size: 20)], excludingPID: 99)
    #expect(parsed.map(\.windowID) == [1])
}
