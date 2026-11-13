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
