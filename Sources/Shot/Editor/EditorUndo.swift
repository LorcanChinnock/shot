import AppKit
import ShotCore

/// ⌘Z, ⇧⌘Z and Edit › Undo and Redo in the image and video editors, wherever focus is: a text field being typed in
/// undoes its own typing first, and once it has none left, editing ends and the editor undoes, as the Undo button does.
/// `UndoRoute` decides which.
@MainActor
struct EditorUndo {
    let canUndo: () -> Bool
    let canRedo: () -> Bool
    let undo: () -> Void
    let redo: () -> Void
    /// Ends typing in whichever field has it, keeping what's typed.
    let finishEditing: () -> Void
    /// Whether text is being typed on the canvas, whose finishing saves a step.
    let isTypingOnCanvas: () -> Bool

    func route(redo: Bool, in window: NSWindow) -> UndoRoute {
        let field = window.firstResponder as? NSText
        let typing = field?.undoManager
        return UndoRoute.choose(
            editingField: field != nil,
            fieldCan: (redo ? typing?.canRedo : typing?.canUndo) ?? false,
            editorCan: redo ? canRedo() : canUndo(),
            redo: redo,
            finishingRecords: isTypingOnCanvas()
        )
    }

    func perform(redo: Bool, in window: NSWindow) {
        switch route(redo: redo, in: window) {
        case .field:
            let typing = window.firstResponder?.undoManager
            if redo {
                typing?.redo()
            } else {
                typing?.undo()
            }
        case .finishEditingThenEditor:
            finishEditing()
            redo ? self.redo() : undo()
        case .editor:
            redo ? self.redo() : undo()
        case .none:
            break
        }
    }

    /// Whether `event` is ⌘Z or ⇧⌘Z, and which.
    static func command(in event: NSEvent) -> (isUndo: Bool, redo: Bool) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.charactersIgnoringModifiers?.lowercased() == "z", flags == .command || flags == [.command, .shift] else {
            return (false, false)
        }
        return (true, flags.contains(.shift))
    }
}
