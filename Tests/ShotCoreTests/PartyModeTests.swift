import Foundation
import Testing
@testable import ShotCore

@Test func partyHueTurnsOnceEachCycle() {
    let period = PartyMode.cycleSeconds
    #expect(PartyMode.hue(at: 0) == 0)
    #expect(abs(PartyMode.hue(at: period / 4) - 0.25) < 1e-9)
    #expect(abs(PartyMode.hue(at: period * 3 + period / 2) - 0.5) < 1e-9)
    #expect(abs(PartyMode.hue(at: -period / 4) - 0.75) < 1e-9)
    for time in stride(from: -20.0, through: 20, by: 0.37) {
        #expect((0..<1).contains(PartyMode.hue(at: time)))
    }
}
