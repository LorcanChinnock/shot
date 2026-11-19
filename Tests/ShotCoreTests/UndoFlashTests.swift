import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

private func box(_ rect: CGRect) -> Annotation {
    Annotation(kind: .shape(.rectangle, rect: rect), color: RGBA.presets[0], lineWidth: 4)
}

@Test func undoFlashOutlinesAMarkThatCameBack() {
    let mark = box(CGRect(x: 10, y: 10, width: 50, height: 30))
    let rects = UndoFlash.rects(from: [], to: [mark])
    #expect(rects.count == 1)
    #expect(rects[0].contains(mark.bounds))
}

@Test func undoFlashOutlinesAMarkThatWentAwayWhereItWas() {
    let mark = box(CGRect(x: 200, y: 100, width: 40, height: 40))
    let rects = UndoFlash.rects(from: [mark], to: [])
    #expect(rects.count == 1)
    #expect(rects[0].contains(mark.bounds))
}

@Test func undoFlashOutlinesOnlyTheMarkThatChanged() {
    let still = box(CGRect(x: 0, y: 0, width: 20, height: 20))
    let moving = box(CGRect(x: 100, y: 100, width: 20, height: 20))
    let moved = moving.moved(by: CGSize(width: 30, height: 0))
    let rects = UndoFlash.rects(from: [still, moving], to: [still, moved])
    #expect(rects.count == 1)
    #expect(rects[0].contains(moved.bounds))
    #expect(!rects[0].contains(still.bounds))
}

@Test func undoFlashSkipsStepsThatChangedNoMark() {
    let a = box(CGRect(x: 0, y: 0, width: 20, height: 20))
    let b = box(CGRect(x: 50, y: 0, width: 20, height: 20))
    #expect(UndoFlash.rects(from: [a, b], to: [a, b]).isEmpty)
    // Only the stacking order changed.
    #expect(UndoFlash.rects(from: [a, b], to: [b, a]).isEmpty)
}

@Test func undoFlashHoldsThenFades() {
    #expect(UndoFlash.opacity(0) == 1)
    #expect(UndoFlash.opacity(UndoFlash.hold) == 1)
    #expect(UndoFlash.opacity(1) == 0)
    #expect(UndoFlash.opacity(2) == 0)
    let samples = stride(from: UndoFlash.hold, through: 1, by: 0.05).map(UndoFlash.opacity)
    #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 >= $1 })
}
