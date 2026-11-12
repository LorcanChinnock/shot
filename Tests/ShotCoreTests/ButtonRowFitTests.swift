import CoreGraphics
import Testing
@testable import ShotCore

@Test func equalSharesSplitTheRoomAfterTheGap() {
    #expect(ButtonRowFit.widths(width: 260, gap: 8, shares: [1, 1]) == [126, 126])
}

@Test func unequalSharesFollowTheBoard() {
    // The browser card: Grant Access is 1.3 times as wide as Use Window.
    #expect(ButtonRowFit.widths(width: 260, gap: 8, shares: [1, 1.3]) == [109, 142])
}

@Test func noSharesOrNoRoomGiveNothing() {
    #expect(ButtonRowFit.widths(width: 260, gap: 8, shares: []) == [])
    #expect(ButtonRowFit.widths(width: 4, gap: 8, shares: [1, 1]) == [0, 0])
}

@Test func aNameWiderThanItsShareStacksTheRow() {
    let widths = ButtonRowFit.widths(width: 260, gap: 8, shares: [1, 1])
    #expect(ButtonRowFit.fits(natural: [80, 126], widths: widths))
    #expect(!ButtonRowFit.fits(natural: [80, 170], widths: widths))
    #expect(!ButtonRowFit.fits(natural: [80], widths: widths))
}
