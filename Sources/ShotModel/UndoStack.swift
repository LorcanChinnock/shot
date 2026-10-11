import Foundation

public struct UndoStack<State> {
    private var past: [State] = []
    private var future: [State] = []

    public init() {}

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// Call with the state *before* a change.
    public mutating func record(_ state: State) {
        past.append(state)
        future.removeAll()
    }

    public mutating func undo(from current: State) -> State? {
        guard let previous = past.popLast() else {
            return nil
        }
        future.append(current)
        return previous
    }

    public mutating func redo(from current: State) -> State? {
        guard let next = future.popLast() else {
            return nil
        }
        past.append(current)
        return next
    }
}

extension UndoStack where State: Equatable {
    /// Records `before`, the state as a gesture such as a drag began, as one step, unless `after`, the state as it
    /// ended, is the same: a drag that ends where it began leaves nothing to undo. Returns whether it recorded.
    @discardableResult
    public mutating func record(_ before: State, endingAt after: State) -> Bool {
        guard before != after else {
            return false
        }
        record(before)
        return true
    }
}
