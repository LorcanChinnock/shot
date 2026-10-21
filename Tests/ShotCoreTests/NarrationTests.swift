import Foundation
import Testing
@testable import ShotCore

private typealias Word = Narration.Word
private typealias Phrase = Narration.Phrase

/// Words as the on-device recogniser gives them, spaces included, from "Click the login button. Now the toolbar is broken."
private let spoken = [
    Word(text: "Click", start: 0, end: 0.36), Word(text: " the", start: 0.36, end: 0.54), Word(text: " login", start: 0.54, end: 0.84),
    Word(text: " button.", start: 0.84, end: 1.32), Word(text: " Now ", start: 1.38, end: 1.56), Word(text: "the ", start: 1.56, end: 1.74),
    Word(text: "toolbar ", start: 1.74, end: 2.22), Word(text: "is ", start: 2.22, end: 2.4), Word(text: "broken.", start: 2.4, end: 2.94),
]

@Test func sentencesBecomePhrasesWithEvenSpacing() {
    #expect(Narration.phrases(spoken) == [
        Phrase(text: "Click the login button.", start: 0, end: 1.32),
        Phrase(text: "Now the toolbar is broken.", start: 1.38, end: 2.94),
    ])
}

@Test func aPauseEndsAPhraseWithoutAFullStop() {
    let words = [Word(text: "open", start: 1, end: 1.3), Word(text: " settings", start: 1.3, end: 1.8), Word(text: " then", start: 3, end: 3.2), Word(text: " wait", start: 3.2, end: 3.5)]
    #expect(Narration.phrases(words).map(\.text) == ["open settings", "then wait"])
    // A shorter gap than the pause keeps them together.
    #expect(Narration.phrases(words, pause: 1.5).map(\.text) == ["open settings then wait"])
}

@Test func aSuffixJoinsTheWordBeforeIt() {
    let words = [Word(text: "it", start: 0, end: 0.2), Word(text: "'s", start: 0.2, end: 0.3), Word(text: " gone", start: 0.3, end: 0.6)]
    #expect(Narration.phrases(words).map(\.text) == ["it's gone"])
}

@Test func aLongRunOnIsSplit() {
    let words = (0 ..< 40).map { Word(text: " word", start: Double($0) * 0.5, end: Double($0) * 0.5 + 0.4) }
    let phrases = Narration.phrases(words, longest: 15)
    #expect(phrases.count == 2)
    #expect(phrases[0].start == 0)
    #expect(phrases[1].start == 15)
    #expect(phrases.allSatisfy { $0.end - $0.start < 15 })
}

@Test func emptyAndBrokenWordsAreLeftOut() {
    let words = [Word(text: " ", start: 0, end: 0.1), Word(text: " late", start: 1.5, end: 1.8), Word(text: "nan", start: .nan, end: 1), Word(text: "early", start: 1, end: 1.2)]
    #expect(Narration.phrases(words).map(\.text) == ["early late"])
    #expect(Narration.phrases([]).isEmpty)
}

@Test func eachPhraseGoesWithTheFrameOnScreenWhenItStarts() {
    let phrases = Narration.phrases(spoken)
    // Frames at 0, 1.4 (just after the first sentence) and 2.9.
    #expect(Narration.align(phrases, to: [0, 1.4, 2.9]) == [[phrases[0], phrases[1]], [], []])
    #expect(Narration.align(phrases, to: [0, 1.3, 2.9]) == [[phrases[0]], [phrases[1]], []])
}

@Test func phrasesBeforeTheFirstFrameGoWithIt() {
    let phrase = Phrase(text: "hello", start: 0.1, end: 0.5)
    #expect(Narration.align([phrase], to: [0.25, 3]) == [[phrase], []])
    #expect(Narration.align([phrase], to: []).isEmpty)
}

@Test func aFrameDecodedAHairLateStillGetsThePhraseStartingAtIt() {
    let phrase = Phrase(text: "now", start: 2, end: 2.5)
    #expect(Narration.align([phrase], to: [0, 2.005]) == [[], [phrase]])
}

@Test func phrasesPastTheCharacterLimitAreCounted() {
    let phrases = (0 ..< 10).map { Phrase(text: String(repeating: "a", count: 80), start: Double($0), end: Double($0) + 0.5) }
    let lineLength = Narration.line(phrases[0]).count
    let fit = Narration.fitting(phrases, characters: lineLength * 3 + 1)
    #expect(fit.kept == Array(phrases.prefix(3)))
    #expect(fit.left == 7)
    #expect(Narration.fitting(phrases).left == 0)
}

@Test func aPhraseReadsWithItsTimes() {
    #expect(Narration.line(Phrase(text: "Now the toolbar is broken.", start: 1.38, end: 2.94)) == "Said at 1.4–2.9s: \"Now the toolbar is broken.\"")
}
