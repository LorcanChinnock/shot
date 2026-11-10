import Testing
@testable import ShotCore

private let login = ["General", "Behaviour", "Open Shot at login", "Start Shot when you log in to your Mac."]

@Test func settingsSearchFindsARowByItsName() {
    #expect(SettingsSearch.matches("login", in: login))
    #expect(SettingsSearch.matches("Open Shot", in: login))
    #expect(!SettingsSearch.matches("microphone", in: login))
}

@Test func settingsSearchFindsARowByItsDescription() {
    #expect(SettingsSearch.matches("your mac", in: login))
}

@Test func settingsSearchFindsARowByItsGroupOrSection() {
    #expect(SettingsSearch.matches("behaviour", in: login))
    #expect(SettingsSearch.matches("general", in: login))
}

@Test func settingsSearchNeedsEveryWord() {
    // Words can come from different fields, in any order.
    #expect(SettingsSearch.matches("mac login", in: login))
    #expect(!SettingsSearch.matches("login camera", in: login))
}

@Test func settingsSearchIgnoresCaseAccentsAndApostrophes() {
    #expect(SettingsSearch.matches("LOGIN", in: login))
    #expect(SettingsSearch.matches("reglages", in: ["Réglages"]))
    #expect(SettingsSearch.matches("Réglages", in: ["reglages"]))
    #expect(SettingsSearch.matches("shot's", in: ["Shot’s windows, panels and toasts."]))
    #expect(SettingsSearch.matches("ｓｏｕｎｄ", in: ["Play capture sound"]))
}

@Test func settingsSearchMatchesInsideWordsForLanguagesWithoutSpaces() {
    #expect(SettingsSearch.matches("録画", in: ["画面録画"]))
}

@Test func settingsSearchWithNothingTypedMatchesEveryRow() {
    #expect(SettingsSearch.matches("", in: login))
    #expect(SettingsSearch.matches("   ", in: login))
    #expect(SettingsSearch.terms(" \n ").isEmpty)
    #expect(SettingsSearch.terms("  Play  Sound ") == ["play", "sound"])
}

@Test func settingsArrowKeysStopAtTheFirstAndLastSection() {
    #expect(SettingsSearch.step(from: 0, by: 1, count: 6) == 1)
    #expect(SettingsSearch.step(from: 0, by: -1, count: 6) == 0)
    #expect(SettingsSearch.step(from: 5, by: 1, count: 6) == 5)
    #expect(SettingsSearch.step(from: 3, by: -1, count: 6) == 2)
    #expect(SettingsSearch.step(from: 0, by: 1, count: 0) == 0)
}
