import Foundation
import Testing
@testable import ShotCore

@Test func aTargetNeedsAWindowAnAppOrADisplayButNotBoth() {
    #expect(AgentTarget(window: "Simulator").problem == nil)
    #expect(AgentTarget(bundleID: "com.apple.iphonesimulator").problem == nil)
    #expect(AgentTarget(window: "docs", bundleID: "com.apple.Safari").problem == nil)
    #expect(AgentTarget(display: 1).problem == nil)
    #expect(AgentTarget().problem?.hasPrefix("needs a window") == true)
    #expect(AgentTarget(window: "  ").problem?.hasPrefix("needs a window") == true)
    #expect(AgentTarget(bundleID: "a", display: 1).problem == "takes a window or a display, not both")
    #expect(AgentTarget(display: 0).problem?.hasPrefix("needs a display numbered from 1") == true)
    #expect(AgentTarget(display: 1, noShadow: true).problem == "can leave out only a window's shadow; a display has none")
}

@Test func aRectAndAWaitMustBeInRange() {
    #expect(AgentTarget(window: "a", rect: [0, 0, 1, 1]).problem == nil)
    for rect in [[0, 0, 0, 1], [-1, 0, 5, 5], [0, 0, 5], [0, 0, .infinity, 5], [0, .nan, 5, 5]] as [[Double]] {
        #expect(AgentTarget(window: "a", rect: rect).problem?.hasPrefix("needs a rect") == true, "\(rect)")
    }
    #expect(AgentTarget(window: "a", waitStable: 30).problem == nil)
    #expect(AgentTarget(window: "a", waitStable: 0).problem != nil)
    #expect(AgentTarget(window: "a", waitStable: 30.5).problem != nil)
}

@Test func theAreaIsTheRectWithinTheBoundsCutToThem() {
    let window = CGRect(x: 100, y: 50, width: 400, height: 300)
    #expect(AgentTarget(window: "a").area(in: window) == window)
    #expect(AgentTarget(window: "a", rect: [10, 20, 100, 50]).area(in: window) == CGRect(x: 110, y: 70, width: 100, height: 50))
    #expect(AgentTarget(window: "a", rect: [350, 250, 100, 100]).area(in: window) == CGRect(x: 450, y: 300, width: 50, height: 50))
    #expect(AgentTarget(window: "a", rect: [400, 0, 10, 10]).area(in: window) == nil)
}

@Test func thePixelsAreTheRectAtTheImagesScaleRoundedOutward() {
    #expect(AgentTarget(window: "a").pixels(width: 800, height: 600, scale: 2) == CGRect(x: 0, y: 0, width: 800, height: 600))
    #expect(AgentTarget(window: "a", rect: [10, 20, 100, 50]).pixels(width: 800, height: 600, scale: 2) == CGRect(x: 20, y: 40, width: 200, height: 100))
    #expect(AgentTarget(window: "a", rect: [0.25, 0, 10.5, 10]).pixels(width: 800, height: 600, scale: 2) == CGRect(x: 0, y: 0, width: 22, height: 20))
    #expect(AgentTarget(window: "a", rect: [350, 250, 100, 100]).pixels(width: 800, height: 600, scale: 2) == CGRect(x: 700, y: 500, width: 100, height: 100))
    #expect(AgentTarget(window: "a", rect: [400, 0, 10, 10]).pixels(width: 800, height: 600, scale: 2) == nil)
    #expect(AgentTarget(window: "a", rect: [10, 10, 5000, 20]).rectText == "rect 10,10,5000,20")
}

@Test func waitingStopsOnceTwoSamplesMatchOrAtTheTimeout() {
    let black = [UInt8](repeating: 0, count: 100)
    let white = [UInt8](repeating: 255, count: 100)
    var nearlyBlack = black
    nearlyBlack[0] = 20
    var wait = StableWait(timeout: 1)
    #expect(wait.add(black, elapsed: 0) == .wait)
    #expect(wait.add(white, elapsed: 0.2) == .wait)
    #expect(wait.add(black, elapsed: 0.4) == .wait)
    // A caret blinking in one corner still counts as settled.
    #expect(wait.add(nearlyBlack, elapsed: 0.6) == .settled)

    var never = StableWait(timeout: 0.5)
    #expect(never.add(black, elapsed: 0) == .wait)
    #expect(never.add(white, elapsed: 0.2) == .wait)
    #expect(never.add(black, elapsed: 0.5) == .timedOut)
}
