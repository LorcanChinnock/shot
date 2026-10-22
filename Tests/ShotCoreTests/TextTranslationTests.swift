import Foundation
import Testing
@testable import ShotCore

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 300, height: CGFloat = 20) -> CaptureText.Line {
    CaptureText.Line(text: text, box: CGRect(x: x, y: y, width: width, height: height))
}

private func capture(_ lines: [CaptureText.Line]) -> CaptureText {
    CaptureText(width: 1000, height: 1000, lines: lines)
}

@Test func wrappedLinesJoinIntoOneParagraph() {
    let paragraphs = TextTranslation.paragraphs(capture([
        line("Your changes couldn't be saved because", x: 40, y: 100),
        line("the disk is full. Free up some space and", x: 40, y: 124),
        line("try again.", x: 41, y: 148, width: 80),
        line("Cancel", x: 40, y: 200, width: 60),
        line("Try Again", x: 140, y: 200, width: 80),
    ]))
    #expect(paragraphs == [
        "Your changes couldn't be saved because the disk is full. Free up some space and try again.",
        "Cancel",
        "Try Again",
    ])
}

@Test func aHeadingAndItsBodyStaySeparate() {
    let paragraphs = TextTranslation.paragraphs(capture([
        line("Settings", x: 40, y: 40, height: 34),
        line("Choose how Shot saves your captures.", x: 40, y: 78),
    ]))
    #expect(paragraphs == ["Settings", "Choose how Shot saves your captures."])
}

@Test func linesFarApartStaySeparate() {
    let paragraphs = TextTranslation.paragraphs(capture([
        line("Open at login", x: 40, y: 100),
        line("Show in menu bar", x: 40, y: 140),
    ]))
    #expect(paragraphs == ["Open at login", "Show in menu bar"])
}

@Test func aHyphenatedWordJoinsWithoutASpace() {
    let paragraphs = TextTranslation.paragraphs(capture([
        line("This is an extra-", x: 40, y: 100),
        line("ordinary line.", x: 40, y: 122),
        line(" ", x: 40, y: 400),
    ]))
    #expect(paragraphs == ["This is an extraordinary line."])
}

@Test func theOutputIsOneParagraphALine() {
    #expect(TextTranslation.output(["Hallo Welt ", "", " Abbrechen"]) == "Hallo Welt\nAbbrechen")
}

@Test func theSourceLanguageComesFromTheText() {
    #expect(TextTranslation.language(of: ["Die Änderungen konnten nicht gespeichert werden, weil die Festplatte voll ist."])?.languageCode == "de")
    #expect(TextTranslation.language(of: []) == nil)
}

@Test func regionalVariantsCountAsTheSameLanguage() {
    #expect(TextTranslation.same(Locale.Language(identifier: "en-GB"), Locale.Language(identifier: "en")))
    #expect(!TextTranslation.same(Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "zh-Hant")))
    #expect(!TextTranslation.same(Locale.Language(identifier: "de"), Locale.Language(identifier: "en")))
}

@Test func aLanguageIsNamedInTheUsersLocale() {
    #expect(TextTranslation.name(Locale.Language(identifier: "de"), in: Locale(identifier: "en")) == "German")
}
