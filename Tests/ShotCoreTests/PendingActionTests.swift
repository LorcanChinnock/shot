import Testing
@testable import ShotCore

@MainActor
private final class Log {
    var entries: [String] = []

    func pending() -> PendingAction {
        PendingAction(commit: { self.entries.append("commit") }, undo: { self.entries.append("undo") })
    }
}

@MainActor
@Test func pendingActionCommitsOnce() {
    let log = Log()
    let pending = log.pending()
    pending.commit()
    pending.commit()
    pending.undo()
    #expect(log.entries == ["commit"])
}

@MainActor
@Test func pendingActionUndoCancelsCommit() {
    let log = Log()
    let pending = log.pending()
    pending.undo()
    pending.commit()
    pending.undo()
    #expect(log.entries == ["undo"])
}
