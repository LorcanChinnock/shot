/// An action held back so it can still be undone; exactly one of `commit` or `undo` runs, once.
@MainActor
public final class PendingAction {
    private var commitAction: (() -> Void)?
    private var undoAction: (() -> Void)?

    public init(commit: @escaping () -> Void, undo: @escaping () -> Void) {
        commitAction = commit
        undoAction = undo
    }

    public func commit() {
        let action = commitAction
        settle()
        action?()
    }

    public func undo() {
        let action = undoAction
        settle()
        action?()
    }

    private func settle() {
        commitAction = nil
        undoAction = nil
    }
}
