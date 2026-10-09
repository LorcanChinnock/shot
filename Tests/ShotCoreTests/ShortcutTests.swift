import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

@Test func aShortcutTakenByAnotherActionOrMacOSConflicts() {
    let area = KeyCombo(keyCode: 21, modifiers: KeyCombo.command | KeyCombo.shift)
    let bindings: [ShotAction: KeyCombo] = [.captureArea: area]
    #expect(ShotAction.record.conflict(for: area, bindings: bindings) == .taken(by: .captureArea))
    // Its own shortcut, recorded again, is no conflict.
    #expect(ShotAction.captureArea.conflict(for: area, bindings: bindings) == nil)
    #expect(ShotAction.record.conflict(for: KeyCombo(keyCode: 12, modifiers: KeyCombo.command), bindings: bindings) == .reserved)
    #expect(ShotAction.record.conflict(for: KeyCombo(keyCode: 49, modifiers: KeyCombo.command), bindings: [:]) == .reserved)
    // ⇧⌘Q is free: only the plain ⌘ keys are everyone's.
    #expect(ShotAction.record.conflict(for: KeyCombo(keyCode: 12, modifiers: KeyCombo.command | KeyCombo.shift), bindings: bindings) == nil)
    #expect(ShotAction.Conflict.taken(by: .captureArea).message(for: area) == "⇧⌘4 is already Capture Area")
}

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

@Test func editingAndArrowKeysHaveLabels() {
    #expect(KeyCombo(keyCode: 36, modifiers: KeyCombo.command | KeyCombo.shift).displayString == "⇧⌘↩")
    for code: UInt32 in [36, 48, 53, 51, 117, 123, 124, 125, 126, 115, 119, 116, 121, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92] {
        #expect(!KeyCombo(keyCode: code, modifiers: 0).keyLabel.hasPrefix("#"))
    }
}
