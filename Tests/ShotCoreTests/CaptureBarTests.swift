import CoreGraphics
@testable import ShotCore
import Testing

@Test func captureBarModeFollowsTargetAndPage() {
    #expect(CaptureBarMode(target: .area, browserPage: true) == .area)
    #expect(CaptureBarMode(target: .window, browserPage: false) == .window)
    #expect(CaptureBarMode(target: .window, browserPage: true) == .browser)
    #expect(CaptureBarMode(target: .screen, browserPage: true) == .screen)
}

@Test func captureBarModeRoundTripsThroughItsTarget() {
    for mode in CaptureBarMode.allCases {
        #expect(CaptureBarMode(target: mode.target, browserPage: mode.picksPage) == mode)
    }
    #expect(CaptureBarMode.browser.target == .window)
    #expect(CaptureBarMode.browser.key == "B")
    #expect(CaptureBarMode.screen.key == "Tab")
}

@Test func captureBarLaysOutGroupsWithDividers() {
    let layout = CaptureBarLayout(groups: [[80, 38], [34], [34, 34]], height: 34)
    // 6 padding, 80, 4 gap, 38, then 4 gap + 4 margin to the divider.
    #expect(layout.frames[0] == [CGRect(x: 6, y: 6, width: 80, height: 34), CGRect(x: 90, y: 6, width: 38, height: 34)])
    #expect(layout.dividers == [136, 187])
    // Divider at 136, 1 wide, then 4 margin and 4 gap after it.
    #expect(layout.frames[1] == [CGRect(x: 145, y: 6, width: 34, height: 34)])
    #expect(layout.frames[2].map(\.minX) == [196, 234])
    #expect(layout.size == CGSize(width: 274, height: 46))
}

@Test func captureBarSkipsEmptyGroups() {
    let layout = CaptureBarLayout(groups: [[50], [], [34]], height: 34)
    #expect(layout.frames.count == 2)
    #expect(layout.dividers == [64])
    // 6 + 50 + 4 gap + 4 margin + 1 + 4 margin + 4 gap + 34 + 6.
    #expect(layout.size.width == 113)
}

@Test func captureBarWithNothingIsJustPadding() {
    let layout = CaptureBarLayout(groups: [], height: 34)
    #expect(layout.frames.isEmpty)
    #expect(layout.size == CGSize(width: 12, height: 46))
}
