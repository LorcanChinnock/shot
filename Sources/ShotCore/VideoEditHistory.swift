import Foundation

/// What one undo step of the video editor restores. The export options are part of it on purpose, so ⌘Z also takes back a change of format.
public struct VideoEdit: Equatable, Sendable {
    public var project: Project
    public var options: VideoExportOptions

    public init(project: Project, options: VideoExportOptions) {
        self.project = project
        self.options = options
    }
}

/// The video editor's undo steps, and which changes join the step before them.
public struct VideoEditHistory {
    private var stack = UndoStack<VideoEdit>()
    /// What the latest undo step changed, while it's still the latest, so a run of changes to it (a colour picker
    /// dragged) amends that step instead of adding one each.
    private var coalescingKey: String?

    public init() {}

    public var canUndo: Bool { stack.canUndo }
    public var canRedo: Bool { stack.canRedo }

    /// Forgets every step, as when the file is loaded again.
    public mutating func reset() {
        self = VideoEditHistory()
    }

    /// Makes the next change its own step, even with the same key as the last.
    public mutating func stopCoalescing() {
        coalescingKey = nil
    }

    /// Records `before` as one step that nothing can join.
    public mutating func record(_ before: VideoEdit) {
        stack.record(before)
        coalescingKey = nil
    }

    /// Records `before`, the edit as a change is about to leave it, as a step, unless this change has the key of the last one
    /// and so amends that step. A change that isn't `recording` is part of the last step, and one with no key is always a new one.
    public mutating func recordChange(from before: VideoEdit, recording: Bool = true, coalescing key: String? = nil) {
        guard recording, key == nil || key != coalescingKey else {
            return
        }
        stack.record(before)
        coalescingKey = key
    }

    public mutating func undo(from current: VideoEdit) -> VideoEdit? {
        stack.undo(from: current)
    }

    public mutating func redo(from current: VideoEdit) -> VideoEdit? {
        stack.redo(from: current)
    }
}
