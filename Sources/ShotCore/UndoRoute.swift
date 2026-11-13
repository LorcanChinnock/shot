import Foundation

/// Where ⌘Z, ⇧⌘Z and Edit › Undo and Redo go in the image and video editors, so they work whenever the title bar's Undo
/// button would, typing included.
public enum UndoRoute: Equatable, Sendable {
    /// The text field being typed in undoes its own typing, as any Mac text field does.
    case field
    /// The field has nothing left to undo, so editing ends, which keeps what's typed, and the editor undoes its last step.
    case finishEditingThenEditor
    /// The editor undoes its last step, as the Undo button does.
    case editor
    /// Nothing to undo, so the menu item is greyed out and the key does nothing.
    case none

    /// The route for an undo, or a redo, given whether a text field is being typed in, whether it can undo (or redo) its
    /// typing, and whether the editor can.
    public static func choose(editingField: Bool, fieldCan: Bool, editorCan: Bool) -> UndoRoute {
        if editingField, fieldCan {
            return .field
        }
        guard editorCan else {
            return .none
        }
        return editingField ? .finishEditingThenEditor : .editor
    }

    /// Whether Edit › Undo or Redo is enabled.
    public var isEnabled: Bool { self != .none }
}
