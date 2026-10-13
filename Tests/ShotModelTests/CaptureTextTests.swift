import Foundation
import Testing
@testable import ShotModel

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

private func found(_ text: String, _ kinds: Set<SensitiveText.Kind> = Set(SensitiveText.Kind.allCases)) -> [String] {
    SensitiveText.matches(in: text, kinds: kinds).map { "\($0.kind.rawValue): \(text[$0.range])" }
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

@Test func aRangeBoxesTheWholeWordsItTouches() throws {
    let line = spaced("Email jane@example.com today")
    let range = try #require(line.text.range(of: "example"))
    #expect(line.box(of: range) == CGRect(x: 60, y: 40, width: 160, height: 20))
    let both = try #require(line.text.range(of: "l jane"))
    #expect(line.box(of: both) == CGRect(x: 0, y: 40, width: 220, height: 20))
}

@Test func aRangeBoxesTheLineWhenItsWordsDontLineUp() throws {
    var line = spaced("two words")
    line.words.removeLast()
    #expect(line.box(of: try #require(line.text.range(of: "words"))) == line.box)
}

// MARK: Finding

@Test func aQueryMatchesLinesIgnoringCaseAndAccentsWithTheBoxOfItsWords() {
    let text = CaptureText(width: 400, height: 100, lines: [spaced("Résumé saved"), spaced("Save changes")])
    let hits = text.lines(matching: " resume ")
    #expect(hits.map(\.line.text) == ["Résumé saved"])
    #expect(hits.first?.box == CGRect(x: 0, y: 40, width: 60, height: 20))
    #expect(text.lines(matching: "SAVE").map(\.line.text) == ["Résumé saved", "Save changes"])
    #expect(text.lines(matching: "  ").isEmpty)
    #expect(text.lines(matching: "delete").isEmpty)
}

@Test func jsonGivesBoxesAsXYWidthHeightAndWordsOnlyWhenAsked() {
    var first = spaced("Save now")
    first.confidence = 0.876
    let text = CaptureText(width: 400, height: 100, lines: [first])
    #expect(text.json(words: false) == [
        "size": .object(["width": .number(400), "height": .number(100)]),
        "text": .string("Save now"),
        "lines": .array([.object(["text": .string("Save now"), "box": .array([0, 40, 80, 20].map(JSONValue.number))])]),
    ])
    #expect(text.json(words: true)["lines"] == .array([.object([
        "text": .string("Save now"),
        "box": .array([0, 40, 80, 20].map(JSONValue.number)),
        "confidence": .number(0.88),
        "words": .array([
            .object(["text": .string("Save"), "box": .array([0, 40, 40, 20].map(JSONValue.number))]),
            .object(["text": .string("now"), "box": .array([50, 40, 30, 20].map(JSONValue.number))]),
        ]),
    ])]))
}

// MARK: Emails

@Test func emailsAreFoundInsideOtherText() {
    #expect(found("Contact: jane.doe+shot@mail.example.co.uk, or bob@x.io.") == ["email: jane.doe+shot@mail.example.co.uk", "email: bob@x.io"])
    #expect(found("an @mention and user@localhost").isEmpty)
}

// MARK: Cards

@Test func theLuhnCheckTakesValidNumbersOnly() {
    #expect(SensitiveText.luhn("4242424242424242"))
    #expect(SensitiveText.luhn("378282246310005"))
    #expect(SensitiveText.luhn("5555555555554444"))
    #expect(!SensitiveText.luhn("4242424242424241"))
    #expect(!SensitiveText.luhn(""))
    #expect(!SensitiveText.luhn("4242x42424242424"))
}

@Test func cardNumbersAreFoundWithSpacesHyphensOrNeither() {
    #expect(found("Card 4242 4242 4242 4242") == ["card: 4242 4242 4242 4242"])
    #expect(found("Amex 3782-822463-10005 on file") == ["card: 3782-822463-10005"])
    #expect(found("5555555555554444") == ["card: 5555555555554444"])
}

@Test func aCardFollowedByMoreDigitsIsStillFound() {
    #expect(found("4242 4242 4242 4242 12 34 567") == ["card: 4242 4242 4242 4242"])
}

@Test func numbersThatFailLuhnOrNoCardStartsWithArentCards() {
    #expect(found("Order 4242 4242 4242 4241").isEmpty)
    // Passes Luhn, but no card network's numbers start with 1.
    #expect(found("Ref 1000000000000008").isEmpty)
    #expect(found("Call 555-0100 at 12:30").isEmpty)
}

// MARK: Tokens

@Test func keysWithKnownPrefixesAreTokens() {
    #expect(found("OPENAI_API_KEY=sk-proj-abcdefghijklmnop1234") == ["token: sk-proj-abcdefghijklmnop1234"])
    #expect(found("token ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") == ["token: ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
    #expect(found("AKIAIOSFODNN7EXAMPLE") == ["token: AKIAIOSFODNN7EXAMPLE"])
    #expect(found("xoxb-1234567890-abcdefghij") == ["token: xoxb-1234567890-abcdefghij"])
}

@Test func jsonWebTokensAreTokens() {
    let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
    #expect(found("Authorization: Bearer \(jwt)") == ["token: \(jwt)"])
}

@Test func longRandomStringsAreTokens() {
    #expect(found("secret: Xk9vQ2mZ7pL4rT8wB3nY6cH1") == ["token: Xk9vQ2mZ7pL4rT8wB3nY6cH1"])
}

@Test func identifiersHashesAndShortStringsArentTokens() {
    #expect(found("CaptureCoordinatorTests2 failed").isEmpty)
    #expect(found("commit 98b4748c2e1f0a9d3b6e5f7a8c9d0e1f2a3b4c5d").isEmpty)
    #expect(found("id 3f2504e0-4f89-11d3-9a0c-0305e82c3301").isEmpty)
    #expect(found("Xk9vQ2mZ7pL4").isEmpty)
    #expect(found("Screenshot-2026-10-12-at-14.03.12").isEmpty)
}

// MARK: Together

@Test func onlyTheKindsAskedForAreFound() {
    let text = "jane@example.com 4242424242424242 sk-abcdefghijklmnopqrstu"
    #expect(found(text) == ["email: jane@example.com", "card: 4242424242424242", "token: sk-abcdefghijklmnopqrstu"])
    #expect(found(text, [.card]) == ["card: 4242424242424242"])
}

@Test func anEmailIsntAlsoAToken() {
    #expect(found("Xk9vQ2mZ7pL4rT8wB3nY6cH1@example.com") == ["email: Xk9vQ2mZ7pL4rT8wB3nY6cH1@example.com"])
}

@Test func sensitiveTextComesWithTheBoxToHide() {
    let text = CaptureText(width: 400, height: 100, lines: [spaced("Mail jane@example.com now")])
    #expect(text.sensitive() == [CaptureText.Found(kind: .email, text: "jane@example.com", box: CGRect(x: 50, y: 40, width: 160, height: 20))])
    #expect(text.sensitive([.card]).isEmpty)
}

@Test func whatToHideHasOneFindForEachBox() {
    // The email and the card are one word, so they share its box and it's hidden once.
    let text = CaptureText(width: 700, height: 100, lines: [spaced("Pay jane@example.com,4242424242424242 or sk-abcdefghijklmnopqrstu")])
    #expect(text.sensitive().count == 3)
    let hidden = text.toHide(Set(SensitiveText.Kind.allCases))
    #expect(hidden.map(\.kind) == [.email, .token])
    // Each word's box, grown by 5 px (a quarter of its 20 px height) at the sides and 4 px top and bottom.
    #expect(hidden.map(\.box) == [CGRect(x: 35, y: 36, width: 340, height: 28), CGRect(x: 405, y: 36, width: 250, height: 28)])
    #expect(text.toHide([.card]).map(\.kind) == [.card])
}

@Test func whatToHideStaysOnTheImage() {
    // The email touches the top and right edges, so the padding stops there and grows only left and down.
    let box = CGRect(x: 140, y: 0, width: 160, height: 20)
    let line = CaptureText.Line(text: "jane@example.com", box: box, words: [.init(text: "jane@example.com", box: box)])
    #expect(CaptureText(width: 300, height: 100, lines: [line]).toHide([.email])[0].box == CGRect(x: 135, y: 0, width: 165, height: 24))
}

@Test func whatToHideStopsShortOfTheNextWord() {
    // Word boxes nearly touch, so the email grows only 1 px towards each neighbour, stopping 1 px short of it, but the full 2 px up and down.
    let words: [CaptureText.Word] = [
        .init(text: "Contact", box: CGRect(x: 40, y: 62, width: 95, height: 10)),
        .init(text: "jane@example.com", box: CGRect(x: 137, y: 62, width: 253, height: 10)),
        .init(text: "today", box: CGRect(x: 392, y: 62, width: 75, height: 10)),
    ]
    let line = CaptureText.Line(text: "Contact jane@example.com today", box: CGRect(x: 40, y: 62, width: 427, height: 10), words: words)
    #expect(CaptureText(width: 700, height: 200, lines: [line]).toHide([.email])[0].box == CGRect(x: 136, y: 60, width: 255, height: 14))
}

@Test func smallTextIsPaddedByAtLeastTwoPixels() {
    let line = CaptureText.Line(text: "jane@example.com", box: CGRect(x: 10, y: 10, width: 60, height: 4), words: [.init(text: "jane@example.com", box: CGRect(x: 10, y: 10, width: 60, height: 4))])
    let box = CaptureText(width: 100, height: 100, lines: [line]).toHide([.email])[0].box
    #expect(box == CGRect(x: 8, y: 8, width: 64, height: 8))
}

@Test func whatWasHiddenIsReportedWithoutItsText() {
    let hidden = [CaptureText.Found(kind: .email, text: "jane@example.com", box: CGRect(x: 50, y: 40, width: 160, height: 20))]
    #expect(CaptureText.json(hidden: hidden) == .array([
        .object(["kind": .string("email"), "box": .array([50, 40, 160, 20].map(JSONValue.number))]),
    ]))
}

@Test func kindsAreNamedInAListSplitByCommas() {
    #expect(SensitiveText.Kind.list("email") == [.email])
    #expect(SensitiveText.Kind.list("Email, TOKEN,card") == [.email, .token, .card])
    #expect(SensitiveText.Kind.list("email,email") == [.email])
    #expect(SensitiveText.Kind.list("email,phone") == nil)
    #expect(SensitiveText.Kind.list("") == nil)
    #expect(SensitiveText.Kind.list(",") == nil)
}
