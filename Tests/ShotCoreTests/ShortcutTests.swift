import Foundation
import Testing
@testable import ShotCore

@Test func aShortcutTakenByAnotherActionOrMacOSConflicts() {
    let area = KeyCombo(keyCode: 21, modifiers: KeyCombo.command | KeyCombo.shift)
    let bindings: [ShotAction: KeyCombo] = [.screenshot: area]
    #expect(ShotAction.record.conflict(for: area, bindings: bindings) == .taken(by: .screenshot))
    // Its own shortcut, recorded again, is no conflict.
    #expect(ShotAction.screenshot.conflict(for: area, bindings: bindings) == nil)
    #expect(ShotAction.record.conflict(for: KeyCombo(keyCode: 12, modifiers: KeyCombo.command), bindings: bindings) == .reserved)
    #expect(ShotAction.record.conflict(for: KeyCombo(keyCode: 49, modifiers: KeyCombo.command), bindings: [:]) == .reserved)
    // ⇧⌘Q is free: only the plain ⌘ keys are everyone's.
    #expect(ShotAction.record.conflict(for: KeyCombo(keyCode: 12, modifiers: KeyCombo.command | KeyCombo.shift), bindings: bindings) == nil)
}

@Test func editingAndArrowKeysHaveLabels() {
    #expect(KeyCombo(keyCode: 36, modifiers: KeyCombo.command | KeyCombo.shift).displayString == "⇧⌘↩")
    for code: UInt32 in [36, 48, 53, 51, 117, 123, 124, 125, 126, 115, 119, 116, 121, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92] {
        #expect(!KeyCombo(keyCode: code, modifiers: 0).keyLabel.hasPrefix("#"))
    }
}
