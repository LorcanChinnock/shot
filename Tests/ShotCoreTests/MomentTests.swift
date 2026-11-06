import Foundation
import Testing
@testable import ShotCore

struct MomentTests {
    @Test(arguments: Moment.allCases.filter { !$0.isAmbient })
    func actionMomentsStayUnder300ms(_ moment: Moment) {
        #expect(moment.duration < 0.3)
    }

    @Test func reduceMotionFadesOnlyTheMomentsTheSpecSays() {
        #expect(Moment.allCases.filter { $0.reduced == .fade } == [.viewfinderSnap, .tick, .panelArrive])
        #expect(Moment.reducedFade == 0.12)
    }

    @Test func specTimings() {
        #expect(Moment.press.duration == 0.08)
        #expect(Moment.viewfinderSnap.duration == 0.18)
        #expect(Moment.tick.duration == 0.24)
        #expect(Moment.markLand.duration == 0.2)
        #expect(Moment.panelArrive.duration == 0.24)
        #expect(Moment.recordingPulse.duration == 1.6)
    }

    @Test func popOvershootsThenSettles() {
        #expect(Moment.popScale(0) > 0)
        #expect(Moment.popScale(0) < 0.1)
        #expect(abs(Moment.popScale(0.6) - 1.22) < 1e-9)
        #expect(Moment.popScale(1) == 1)
        #expect(Moment.popScale(2) == 1)
        let samples = stride(from: 0.0, through: 1, by: 0.01).map(Moment.popScale)
        #expect(samples.max()! <= 1.22 + 1e-9)
    }

    @Test func flipFoldsTheOldDigitThenUnfoldsTheNew() {
        #expect(Moment.flip(0) == (true, 1))
        #expect(Moment.flip(0.25) == (true, 0.5))
        #expect(Moment.flip(0.5) == (false, 0))
        #expect(Moment.flip(1) == (false, 1))
    }

    @Test func pulseBreathesOutThenRests() {
        #expect(Moment.pulse(0) == (0, 0.5))
        #expect(Moment.pulse(0.6) == (1, 0))
        #expect(Moment.pulse(0.9) == (1, 0))
        let next = Moment.pulse(1.3)
        let same = Moment.pulse(0.3)
        #expect(abs(next.spread - same.spread) < 1e-9)
        #expect(Moment.pulse(0.3).opacity < 0.5)
    }
}
