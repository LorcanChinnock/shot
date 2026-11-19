import Foundation
import Testing
@testable import ShotCore

@Test func aRecentColourGoesToTheFront() {
    let teal = RGBA(0, 0.5, 0.5)
    let plum = RGBA(0.5, 0, 0.5)
    #expect(RecentColors.adding(plum, to: [teal]) == [plum, teal])
}

@Test func aRecentColourPickedAgainMovesToTheFrontOnce() {
    let teal = RGBA(0, 0.5, 0.5)
    let plum = RGBA(0.5, 0, 0.5)
    // The editor's HSB round trip leaves noise below a hex step, which still counts as the same colour.
    let nearlyTeal = RGBA(0.000_01, 0.5, 0.5)
    #expect(RecentColors.adding(nearlyTeal, to: [plum, teal]) == [nearlyTeal, plum])
}

@Test func recentColoursKeepOnlyTheNewest() {
    let list = (0..<RecentColors.limit).map { RGBA(CGFloat($0) / 20 + 0.01, 0.3, 0.6) }
    let added = RecentColors.adding(RGBA(0.9, 0.1, 0.2), to: list)
    #expect(added.count == RecentColors.limit)
    #expect(added.first == RGBA(0.9, 0.1, 0.2))
    #expect(added.last == list[RecentColors.limit - 2])
}

@Test func aPresetIsNotARecentColour() {
    #expect(RecentColors.adding(RGBA.presets[0], to: []).isEmpty)
}

@Test func recentColoursRoundTripAndSurviveBadData() {
    let list = [RGBA(0, 0.5, 0.5), RGBA(0.5, 0, 0.5, 0.4)]
    #expect(RecentColors.decode(RecentColors.encode(list)) == list)
    #expect(RecentColors.decode(Data()).isEmpty)
    #expect(RecentColors.decode(Data("nope".utf8)).isEmpty)
}
