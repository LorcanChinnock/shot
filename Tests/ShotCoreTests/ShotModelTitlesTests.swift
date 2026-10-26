import Foundation
import Testing
@testable import ShotCore

@Test func aConflictNamesTheActionThatHasTheShortcut() {
    let area = KeyCombo(keyCode: 21, modifiers: KeyCombo.command | KeyCombo.shift)
    #expect(ShotAction.Conflict.taken(by: .captureArea).message(for: area) == "⇧⌘4 is already used by Capture Area")
}
