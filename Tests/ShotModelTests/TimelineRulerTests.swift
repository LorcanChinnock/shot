import Foundation
import Testing
@testable import ShotModel

@Test func snapsToTheNearestPointInReach() {
    #expect(Snapping.snap(5.04, to: [0, 5, 5.1, 9], within: 0.05) == 5)
    #expect(Snapping.snap(5.07, to: [0, 5, 5.1, 9], within: 0.05) == 5.1)
    #expect(Snapping.snap(7, to: [0, 5, 9], within: 0.5) == nil)
    #expect(Snapping.snap(1, to: [], within: 1) == nil)
}

@Test func zoomStaysInRangeAndStepsBothWays() {
    #expect(TimelineZoom.zoomed(1, bySteps: -3) == 1)
    #expect(TimelineZoom.zoomed(60, bySteps: 5) == 64)
    #expect(TimelineZoom.zoomed(1, bySteps: 2) == 2.25)
    #expect(abs(TimelineZoom.zoomed(TimelineZoom.zoomed(1, bySteps: 3), bySteps: -3) - 1) < 1e-9)
}

@Test func zoomingKeepsTheAnchorTimeUnderTheCursor() {
    // 10 s over 800 pt at 4× is 3200 pt wide; 5 s sits at 1600, so to stay at x 400 the view starts at 1200.
    #expect(TimelineZoom.offset(keeping: 5, atViewX: 400, duration: 10, zoom: 4, viewWidth: 800) == 1200)
    #expect(TimelineZoom.offset(keeping: 0.1, atViewX: 400, duration: 10, zoom: 4, viewWidth: 800) == 0)
    #expect(TimelineZoom.offset(keeping: 10, atViewX: 0, duration: 10, zoom: 4, viewWidth: 800) == 2400)
    #expect(TimelineZoom.offset(keeping: 1, atViewX: 0, duration: 0, zoom: 4, viewWidth: 800) == 0)
}

@Test func rulerLabelsStayApartAsYouZoom() {
    #expect(TimelineRuler.interval(pointsPerSecond: 100) == 1)
    #expect(TimelineRuler.interval(pointsPerSecond: 10) == 10)
    #expect(TimelineRuler.interval(pointsPerSecond: 1000) == 0.1)
    #expect(TimelineRuler.interval(pointsPerSecond: 0.001) == 3600)
    #expect(TimelineRuler.interval(pointsPerSecond: 0) == 3600)
}

@Test func rulerTicksRunToTheEnd() {
    #expect(TimelineRuler.ticks(duration: 5, interval: 2) == [0, 2, 4])
    #expect(TimelineRuler.ticks(duration: 4, interval: 2) == [0, 2, 4])
    #expect(TimelineRuler.ticks(duration: 0, interval: 1).isEmpty)
}

@Test func rulerLabelsShowTenthsOnlyWhenTheyMatter() {
    #expect(TimelineRuler.label(65, interval: 5) == "1:05")
    #expect(TimelineRuler.label(1.5, interval: 0.5) == "0:01.5")
    #expect(TimelineRuler.label(0, interval: 10) == "0:00")
}
