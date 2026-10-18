import Foundation
import Testing
@testable import ShotCore

@Test func aConflictNamesTheActionThatHasTheShortcut() {
    let area = KeyCombo(keyCode: 21, modifiers: KeyCombo.command | KeyCombo.shift)
    #expect(ShotAction.Conflict.taken(by: .captureArea).message(for: area) == "⇧⌘4 is already used by Capture Area")
}

@Test func anOriginSaysWhoMadeItHowAndWhen() {
    let made = Date(timeIntervalSince1970: 1_791_640_992)
    let time = made.formatted(date: .omitted, time: .shortened)
    #expect(ProjectOrigin(via: .mcp, client: "claude-code", action: "annotate", date: made).summary(now: made) == "Made by Claude Code · annotate · \(time)")
    #expect(ProjectOrigin(via: .mcp, action: "annotate", date: made).summary(now: made) == "Made by an agent · annotate · \(time)")
    #expect(ProjectOrigin(via: .cli, action: "trim", date: made).summary(now: made) == "Command line · trim · \(time)")
    let nextWeek = made.addingTimeInterval(7 * 86_400)
    #expect(ProjectOrigin(via: .cli, action: "trim", date: made).summary(now: nextWeek) == "Command line · trim · \(made.formatted(date: .abbreviated, time: .shortened))")
}
