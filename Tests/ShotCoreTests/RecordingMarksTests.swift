import CoreGraphics
import Testing
@testable import ShotCore

struct RecordingMarksTests {
    @Test func borderIsTwoPointsWithAFourPointGlow() {
        #expect(RecordingBorder.lineWidth == 2)
        #expect(RecordingBorder.glowWidth == 4)
        #expect(RecordingBorder.outset == 6)
        #expect(RecordingBorder.glowOpacity == 0.22)
    }

    @Test func ringHugsTheAreaAndTheGlowSitsOutsideIt() {
        let area = CGRect(x: 0, y: 0, width: 520, height: 520)
        let bounds = CGRect(origin: .zero, size: area.insetBy(dx: -RecordingBorder.outset, dy: -RecordingBorder.outset).size)
        let ring = RecordingBorder.ring(in: bounds)
        // Its inner edge lands on the area's edge, 6 pt in from the panel's.
        #expect(ring.rect.minX + RecordingBorder.lineWidth / 2 == RecordingBorder.outset)
        #expect(ring.rect.width + RecordingBorder.lineWidth == bounds.width - 2 * RecordingBorder.glowWidth)
        #expect(ring.radius == 1)
        let glow = RecordingBorder.glow(in: bounds)
        // Its outer edge lands on the panel's edge, and its inner edge on the ring's outer edge.
        #expect(glow.rect.minX - RecordingBorder.glowWidth / 2 == 0)
        #expect(glow.rect.minX + RecordingBorder.glowWidth / 2 == ring.rect.minX - RecordingBorder.lineWidth / 2)
        #expect(glow.radius == 4)
    }

    @Test func clickRingMatchesTheBoard() {
        #expect(ClickRing.extent == 52)
        #expect(ClickRing.ringRadius == 18.5)
        #expect(ClickRing.haloRadius == 23)
        let frame = ClickRing.frame(at: CGPoint(x: 100, y: 200))
        #expect(frame.midX == 100)
        #expect(frame.midY == 200)
        #expect(frame.width == 52)
    }

    @Test func clickRingsShowOnlyInsideTheArea() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(ClickRing.shows(at: CGPoint(x: 300, y: 250), in: area))
        #expect(!ClickRing.shows(at: CGPoint(x: 50, y: 250), in: area))
        #expect(!ClickRing.shows(at: CGPoint(x: 300, y: 401), in: area))
    }

    @Test func macOSDrawsTheRingsInAWindowRecording() {
        #expect(ClickRing.drawnByShot(recordsWindow: false))
        #expect(!ClickRing.drawnByShot(recordsWindow: true))
    }

    @Test func ringHoldsThenFades() {
        #expect(ClickRing.opacity(at: 0, reduceMotion: false) == 1)
        #expect(ClickRing.opacity(at: ClickRing.hold - 0.01, reduceMotion: false) == 1)
        let half = ClickRing.opacity(at: ClickRing.hold + Moment.clickRing.duration / 2, reduceMotion: false)
        #expect(abs(half - 0.5) < 1e-9)
        #expect(ClickRing.opacity(at: ClickRing.hold + Moment.clickRing.duration, reduceMotion: false) == 0)
    }

    @Test func reduceMotionKeepsTheRingButDropsItsFade() {
        #expect(ClickRing.opacity(at: 0.1, reduceMotion: true) == 1)
        #expect(ClickRing.opacity(at: ClickRing.hold, reduceMotion: true) == 0)
        #expect(Moment.clickRing.reduced == .none)
    }
}
