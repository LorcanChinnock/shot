import Testing
@testable import ShotCore

struct CountdownRingTests {
    @Test func fullAtTheStartAndEmptyAtTheEnd() {
        #expect(CountdownRing.fraction(remaining: 5, of: 5) == 1)
        #expect(CountdownRing.fraction(remaining: 0, of: 5) == 0)
    }

    @Test func showsTheShareOfSecondsLeft() {
        // The board's panel shows 3 of a 5 s delay with 60% of the ring left.
        #expect(CountdownRing.fraction(remaining: 3, of: 5) == 0.6)
    }

    @Test func drainsOneSecondEachTick() {
        #expect(CountdownRing.target(remaining: 3, of: 3) == CountdownRing.fraction(remaining: 2, of: 3))
        #expect(CountdownRing.target(remaining: 1, of: 10) == 0)
    }

    @Test func staysInRange() {
        #expect(CountdownRing.fraction(remaining: 7, of: 5) == 1)
        #expect(CountdownRing.fraction(remaining: -1, of: 5) == 0)
        #expect(CountdownRing.fraction(remaining: 3, of: 0) == 0)
    }
}
