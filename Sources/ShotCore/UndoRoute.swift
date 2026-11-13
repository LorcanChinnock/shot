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

    /// The route for an undo, or a `redo`, given whether a text field is being typed in, whether it can undo (or redo) its
    /// typing, and whether the editor can. `finishingRecords` says whether ending the editing saves a step, as text typed
    /// on the canvas does: that step would clear what there is to redo, so a redo then goes nowhere.
    public static func choose(editingField: Bool, fieldCan: Bool, editorCan: Bool, redo: Bool = false, finishingRecords: Bool = false) -> UndoRoute {
        if editingField, fieldCan {
            return .field
        }
        guard editorCan else {
            return .none
        }
        guard editingField else {
            return .editor
        }
        return redo && finishingRecords ? .none : .finishEditingThenEditor
    }

    /// Whether Edit › Undo or Redo is enabled.
    public var isEnabled: Bool { self != .none }
}
