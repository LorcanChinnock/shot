import Foundation
import Testing
@testable import ShotCore

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 100, height: CGFloat = 20) -> CaptureText.Line {
    CaptureText.Line(text: text, box: CGRect(x: x, y: y, width: width, height: height))
}

/// A line whose words are each 10 pixels a character with a 10 pixel space, from x 0.
private func spaced(_ text: String) -> CaptureText.Line {
    let words = CaptureText.Line.wordRanges(in: text).map { range in
        CaptureText.Word(
            text: String(text[range]),
            box: CGRect(x: CGFloat(text.distance(from: text.startIndex, to: range.lowerBound)) * 10, y: 40, width: CGFloat(text[range].count) * 10, height: 20)
        )
    }
    return CaptureText.Line(text: text, box: CGRect(x: 0, y: 40, width: CGFloat(text.count) * 10, height: 20), words: words)
}

// MARK: Reading order

@Test func linesReadTopToBottomThenLeftToRight() {
    let ordered = CaptureText.readingOrder([
        line("Body", x: 10, y: 80),
        line("Value", x: 200, y: 42),
        line("Title", x: 10, y: 0),
        line("Label", x: 10, y: 40),
    ])
    #expect(ordered.map(\.text) == ["Title", "Label", "Value", "Body"])
}

@Test func aLineWhoseMiddleIsBelowTheRowStartsANewRow() {
    let ordered = CaptureText.readingOrder([
        line("Lower", x: 0, y: 15),
        line("Upper", x: 300, y: 0),
    ])
    // Lower's middle, 25, is below Upper's bottom, 20, so it reads after it though it's further left.
    #expect(ordered.map(\.text) == ["Upper", "Lower"])
}

@Test func theStringIsEveryLineOnItsOwnLine() {
    let text = CaptureText(width: 400, height: 200, lines: [line("One", x: 0, y: 0), line("Two", x: 0, y: 30)])
    #expect(text.string == "One\nTwo")
}

// MARK: Words

@Test func wordRangesSplitAtAnyRunOfWhitespace() {
    let text = "  Save \t changes  now"
    #expect(CaptureText.Line.wordRanges(in: text).map { String(text[$0]) } == ["Save", "changes", "now"])
    #expect(CaptureText.Line.wordRanges(in: "   ").isEmpty)
}
