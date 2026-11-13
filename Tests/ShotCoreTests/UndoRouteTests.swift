import Testing
@testable import ShotCore

@Test func withNoFieldTheEditorUndoesWheneverItCan() {
    #expect(UndoRoute.choose(editingField: false, fieldCan: false, editorCan: true) == .editor)
    #expect(UndoRoute.choose(editingField: false, fieldCan: false, editorCan: false) == .none)
    // A field that isn't being typed in has no say.
    #expect(UndoRoute.choose(editingField: false, fieldCan: true, editorCan: true) == .editor)
}

@Test func aFieldUndoesItsOwnTypingFirst() {
    #expect(UndoRoute.choose(editingField: true, fieldCan: true, editorCan: true) == .field)
    #expect(UndoRoute.choose(editingField: true, fieldCan: true, editorCan: false) == .field)
}

@Test func withTheTypingUndoneEditingEndsAndTheEditorUndoes() {
    #expect(UndoRoute.choose(editingField: true, fieldCan: false, editorCan: true) == .finishEditingThenEditor)
    #expect(UndoRoute.choose(editingField: true, fieldCan: false, editorCan: false) == .none)
}

@Test func theMenuItemIsEnabledWheneverThereIsSomewhereToGo() {
    #expect(UndoRoute.editor.isEnabled)
    #expect(UndoRoute.field.isEnabled)
    #expect(UndoRoute.finishEditingThenEditor.isEnabled)
    #expect(!UndoRoute.none.isEnabled)
}

@Test func aRedoWhileTypingOnTheCanvasGoesNowhere() {
    // Finishing the text would save a step and clear what there is to redo.
    #expect(UndoRoute.choose(editingField: true, fieldCan: false, editorCan: true, redo: true, finishingRecords: true) == .none)
    #expect(UndoRoute.choose(editingField: true, fieldCan: true, editorCan: true, redo: true, finishingRecords: true) == .field)
    // A field whose finishing saves nothing, such as the size box, still lets the editor redo.
    #expect(UndoRoute.choose(editingField: true, fieldCan: false, editorCan: true, redo: true, finishingRecords: false) == .finishEditingThenEditor)
    // An undo still finishes the text first.
    #expect(UndoRoute.choose(editingField: true, fieldCan: false, editorCan: true, redo: false, finishingRecords: true) == .finishEditingThenEditor)
}
