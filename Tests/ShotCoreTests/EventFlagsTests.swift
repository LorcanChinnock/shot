import CoreGraphics
import Testing
@testable import ShotCore

@Test func modifiersRoundTripThroughEventFlags() {
    let masks = [KeyCombo.command, KeyCombo.shift, KeyCombo.option, KeyCombo.control]
    for subset in 0..<(1 << masks.count) {
        let modifiers = masks.indices.filter { subset & (1 << $0) != 0 }.reduce(UInt32(0)) { $0 | masks[$1] }
        let combo = KeyCombo(keyCode: 21, modifiers: modifiers)
        #expect(KeyCombo(keyCode: 21, eventFlags: combo.eventFlags) == combo)
    }
    // NSEvent.ModifierFlags share CGEventFlags' bits: ⌘ is 1 << 20.
    #expect(KeyCombo(keyCode: 21, eventFlags: CGEventFlags(rawValue: 1 << 20)).modifiers == KeyCombo.command)
}
