import Foundation
import Testing
@testable import ShotCore

@Test func edgeScrollIsStillAwayFromTheEdges() {
    #expect(EdgeScroll.speed(at: 150, length: 300, zone: 30) == 0)
    #expect(EdgeScroll.speed(at: 30, length: 300, zone: 30) == 0)
    #expect(EdgeScroll.speed(at: 270, length: 300, zone: 30) == 0)
}

@Test func edgeScrollSpeedsUpTowardsEachEdge() {
    #expect(EdgeScroll.speed(at: 15, length: 300, zone: 30) == -0.5)
    #expect(EdgeScroll.speed(at: 0, length: 300, zone: 30) == -1)
    #expect(EdgeScroll.speed(at: 285, length: 300, zone: 30) == 0.5)
    #expect(EdgeScroll.speed(at: 300, length: 300, zone: 30) == 1)
}

@Test func edgeScrollKeepsFullSpeedPastTheEdges() {
    #expect(EdgeScroll.speed(at: -40, length: 300, zone: 30) == -1)
    #expect(EdgeScroll.speed(at: 340, length: 300, zone: 30) == 1)
}

@Test func edgeScrollZonesNeverOverlapInAShortViewport() {
    #expect(EdgeScroll.speed(at: 20, length: 40, zone: 30) == 0)
    #expect(EdgeScroll.speed(at: 10, length: 40, zone: 30) == -0.5)
}

@Test func edgeScrollIsStillWithoutAViewport() {
    #expect(EdgeScroll.speed(at: 0, length: 0, zone: 30) == 0)
}

@Test func edgeScrollOffsetStopsAtTheEndsOfTheContent() {
    #expect(EdgeScroll.offset(100, by: 10, content: 600, viewport: 300) == 110)
    #expect(EdgeScroll.offset(5, by: -10, content: 600, viewport: 300) == 0)
    #expect(EdgeScroll.offset(295, by: 10, content: 600, viewport: 300) == 300)
    #expect(EdgeScroll.offset(0, by: 10, content: 200, viewport: 300) == 0)
}
