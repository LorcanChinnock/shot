import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private func makeDocument() -> EditorDocument {
    EditorDocument(base: solidImage(width: 20, height: 20))
}

private func setBackground(_ gray: CGFloat) -> (inout EditorDocument) -> Void {
    { $0.background = RGBA(gray, gray, gray) }
}

@Test func aFreshHistoryIsCleanWithNothingToUndo() {
    let history = EditHistory(saved: makeDocument().snapshot)
    #expect(!history.isDirty)
    #expect(!history.canUndo)
    #expect(!history.canRedo)
}

@Test func anEditIsAnUndoStepAndMakesTheHistoryDirty() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    history.edit(&document, setBackground(0.5))
    #expect(history.isDirty)
    #expect(history.canUndo)
}

@Test func anEditThatChangesNothingIsNoStep() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    history.edit(&document) { _ in }
    #expect(!history.isDirty)
    #expect(!history.canUndo)
}

@Test func undoingBackToTheSavedStateLeavesItClean() {
    var document = makeDocument()
    let original = document.snapshot
    var history = EditHistory(saved: original)
    history.edit(&document, setBackground(0.5))
    let undone = history.undo(&document)
    #expect(undone)
    #expect(document.snapshot == original)
    #expect(!history.isDirty)
    #expect(history.canRedo)
    let redone = history.redo(&document)
    #expect(redone)
    #expect(history.isDirty)
}

@Test func undoAndRedoWithNothingToStepToReturnFalse() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    let undone = history.undo(&document)
    #expect(!undone)
    let redone = history.redo(&document)
    #expect(!redone)
}

@Test func editsWithTheSameKeyInARowAreOneStep() {
    var document = makeDocument()
    let original = document.snapshot
    var history = EditHistory(saved: original)
    history.edit(&document, coalescing: "background", setBackground(0.2))
    history.edit(&document, coalescing: "background", setBackground(0.4))
    history.edit(&document, coalescing: "background", setBackground(0.6))
    history.undo(&document)
    #expect(document.snapshot == original)
    #expect(!history.canUndo)
}

@Test func aDifferentKeyOrNoKeyStartsANewStep() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    history.edit(&document, coalescing: "a", setBackground(0.2))
    history.edit(&document, coalescing: "b", setBackground(0.4))
    history.edit(&document, setBackground(0.6))
    history.undo(&document)
    history.undo(&document)
    history.undo(&document)
    #expect(!history.canUndo)
}

@Test func stoppingCoalescingMakesTheNextEditItsOwnStep() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    history.edit(&document, coalescing: "background", setBackground(0.2))
    history.stopCoalescing()
    history.edit(&document, coalescing: "background", setBackground(0.4))
    history.undo(&document)
    #expect(history.canUndo)
}

@Test func undoEndsCoalescingSoALaterEditIsANewStep() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    history.edit(&document, coalescing: "background", setBackground(0.2))
    history.edit(&document, setBackground(0.9))
    history.undo(&document)
    history.edit(&document, coalescing: "background", setBackground(0.4))
    history.edit(&document, coalescing: "background", setBackground(0.5))
    history.undo(&document)
    #expect(history.canUndo)
}

@Test func aNewEditClearsWhatCouldBeRedone() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    history.edit(&document, setBackground(0.2))
    history.undo(&document)
    history.edit(&document, setBackground(0.4))
    #expect(!history.canRedo)
}

@Test func aGestureUndoesAsOneStep() {
    var document = makeDocument()
    let original = document.snapshot
    var history = EditHistory(saved: original)
    history.beginGesture(document)
    history.apply(&document, setBackground(0.2))
    history.apply(&document, setBackground(0.4))
    #expect(!history.canUndo)
    history.endGesture(document)
    #expect(history.isDirty)
    history.undo(&document)
    #expect(document.snapshot == original)
    #expect(!history.canUndo)
}

@Test func aGestureThatEndsWhereItBeganLeavesNothingToUndo() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    history.beginGesture(document)
    history.apply(&document, setBackground(0.2))
    history.apply(&document) { $0.background = nil }
    history.endGesture(document)
    #expect(!history.canUndo)
    #expect(!history.isDirty)
}

@Test func applyOutsideAGestureIsAStepOfItsOwn() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    history.apply(&document, setBackground(0.2))
    #expect(history.canUndo)
}

@Test func beginningAGestureEndsTheOneInProgress() {
    var document = makeDocument()
    let original = document.snapshot
    var history = EditHistory(saved: original)
    history.beginGesture(document)
    history.apply(&document, setBackground(0.2))
    history.beginGesture(document)
    history.endGesture(document)
    history.undo(&document)
    #expect(document.snapshot == original)
}

@Test func undoEndsAGestureInProgressFirst() {
    var document = makeDocument()
    let original = document.snapshot
    var history = EditHistory(saved: original)
    history.beginGesture(document)
    history.apply(&document, setBackground(0.2))
    history.undo(&document)
    #expect(document.snapshot == original)
}

@Test func savingMakesTheHistoryCleanUnlessTheDocumentMovedOn() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    history.edit(&document, setBackground(0.2))
    let saving = document.snapshot
    history.edit(&document, setBackground(0.4))
    history.didSave(saving, document: document)
    #expect(history.isDirty)
    history.undo(&document)
    #expect(!history.isDirty)
}

@Test func takingASnapshotAsSavedDoesNotMarkTheDocumentChanged() {
    var document = makeDocument()
    var history = EditHistory(saved: document.snapshot)
    document.background = RGBA(0, 0, 0)
    history.setSaved(document.snapshot)
    #expect(!history.isDirty)
    history.edit(&document, setBackground(0.4))
    history.undo(&document)
    #expect(!history.isDirty)
}
