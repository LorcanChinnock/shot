import CoreGraphics
import Testing
@testable import ShotCore

@Test func aRowWithRoomKeepsItsControlBeside() {
    #expect(!SettingRowFit.stacks(width: 400, controlWidth: 200, titleWidth: 60, spacing: 16))
}

@Test func aShortNameNeedsOnlyItsOwnWidth() {
    #expect(!SettingRowFit.stacks(width: 260, controlWidth: 200, titleWidth: 30, spacing: 16))
    #expect(SettingRowFit.stacks(width: 240, controlWidth: 200, titleWidth: 30, spacing: 16))
}

@Test func aLongNameNeedsOnlyTheMinimumBecauseItWraps() {
    #expect(!SettingRowFit.stacks(width: 340, controlWidth: 200, titleWidth: 500, spacing: 16))
    #expect(SettingRowFit.stacks(width: 330, controlWidth: 200, titleWidth: 500, spacing: 16))
}

@Test func aControlWiderThanTheRowStacks() {
    #expect(SettingRowFit.stacks(width: 240, controlWidth: 260, titleWidth: 40, spacing: 16))
}
