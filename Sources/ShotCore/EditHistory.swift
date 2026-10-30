import Foundation

/// The undo steps of an image editor and whether it has changes that aren't saved.
public struct EditHistory {
    private var stack = UndoStack<EditorSnapshot>()
    private var saved: EditorSnapshot
    /// Which property a custom colour pick, a style slider or an arrow key last changed, while that is still the latest
    /// undo step, so dragging through the colour panel or along a slider, or holding an arrow key down, undoes as one step.
    private var coalescingKey: String?
    /// The document as the canvas gesture in progress, a move or resize, began; the gesture undoes as one step when it ends.
    private var gestureStart: EditorSnapshot?
    public private(set) var isDirty = false

    /// `saved` is what the document looks like on disk, so undoing back to it leaves the editor clean.
    public init(saved: EditorSnapshot) {
        self.saved = saved
    }

    public var canUndo: Bool { stack.canUndo }
    public var canRedo: Bool { stack.canRedo }

    /// Applies `change` as one undoable step, or does nothing if it leaves the document as it was.
    /// Calls with the same `key` in a row amend that step instead of adding another.
    public mutating func edit(_ document: inout EditorDocument, coalescing key: String? = nil, _ change: (inout EditorDocument) -> Void) {
        if key != nil, key == coalescingKey {
            change(&document)
            isDirty = true
            return
        }
        let before = document.snapshot
        change(&document)
        guard document.snapshot != before else {
            return
        }
        stack.record(before)
        coalescingKey = key
        isDirty = true
    }

    /// Makes the next edit its own step, even with the same key as the last.
    public mutating func stopCoalescing() {
        coalescingKey = nil
    }

    /// Call as a move or resize on the canvas starts. Its changes, made with `apply`, undo as one step once it ends.
    public mutating func beginGesture(_ document: EditorDocument) {
        endGesture(document)
        gestureStart = document.snapshot
    }

    /// Makes one change of the gesture in progress; outside a gesture it's an undo step of its own.
    public mutating func apply(_ document: inout EditorDocument, _ change: (inout EditorDocument) -> Void) {
        guard gestureStart != nil else {
            edit(&document, change)
            return
        }
        change(&document)
    }

    /// Records the gesture in progress as one undo step, or none if it left the document as it was.
    public mutating func endGesture(_ document: EditorDocument) {
        guard let gestureStart else {
            return
        }
        self.gestureStart = nil
        if stack.record(gestureStart, endingAt: document.snapshot) {
            coalescingKey = nil
            isDirty = true
        }
    }

    /// Steps back, or returns false when there's nothing to undo.
    @discardableResult
    public mutating func undo(_ document: inout EditorDocument) -> Bool {
        endGesture(document)
        coalescingKey = nil
        guard let previous = stack.undo(from: document.snapshot) else {
            return false
        }
        document.restore(previous)
        isDirty = document.snapshot != saved
        return true
    }

    /// Steps forward, or returns false when there's nothing to redo.
    @discardableResult
    public mutating func redo(_ document: inout EditorDocument) -> Bool {
        endGesture(document)
        coalescingKey = nil
        guard let next = stack.redo(from: document.snapshot) else {
            return false
        }
        document.restore(next)
        isDirty = document.snapshot != saved
        return true
    }

    /// Takes `snapshot` as what's on disk without calling the document changed, as when a new capture's style is put on it.
    public mutating func setSaved(_ snapshot: EditorSnapshot) {
        saved = snapshot
    }

    /// Records that `snapshot` was saved while the document may have moved on since.
    public mutating func didSave(_ snapshot: EditorSnapshot, document: EditorDocument) {
        saved = snapshot
        isDirty = document.snapshot != snapshot
    }
}
