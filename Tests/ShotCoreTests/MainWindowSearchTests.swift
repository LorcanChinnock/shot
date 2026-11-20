import Testing
@testable import ShotCore

@Test func mainWindowSearchShowsThePageWithNoWords() {
    #expect(MainWindowSearch.content(query: "", page: .library, settingsMatch: false, showAllCaptures: false) == .page)
    #expect(MainWindowSearch.content(query: "   ", page: .settings, settingsMatch: true, showAllCaptures: true) == .page)
}

@Test func mainWindowSearchFiltersTheLibraryInPlaceWhenNoSettingMatches() {
    #expect(MainWindowSearch.content(query: "invoice", page: .library, settingsMatch: false, showAllCaptures: false) == .filteredLibrary)
    #expect(MainWindowSearch.content(query: "shadow", page: .library, settingsMatch: true, showAllCaptures: false) == .results)
}

@Test func mainWindowSearchAlwaysShowsResultsOnTheSettingsPages() {
    #expect(MainWindowSearch.content(query: "invoice", page: .settings, settingsMatch: false, showAllCaptures: false) == .results)
    #expect(MainWindowSearch.content(query: "shadow", page: .settings, settingsMatch: true, showAllCaptures: false) == .results)
}

@Test func mainWindowSearchShowAllGoesToTheFilteredLibrary() {
    #expect(MainWindowSearch.content(query: "shadow", page: .library, settingsMatch: true, showAllCaptures: true) == .filteredLibrary)
    #expect(MainWindowSearch.content(query: "shadow", page: .settings, settingsMatch: true, showAllCaptures: true) == .filteredLibrary)
}

@Test func mainWindowSearchShowsAtMostEightCaptures() {
    #expect(MainWindowSearch.shownCaptures(of: 0) == 0)
    #expect(MainWindowSearch.shownCaptures(of: 3) == 3)
    #expect(MainWindowSearch.shownCaptures(of: 120) == MainWindowSearch.captureLimit)
}

@Test func mainWindowSearchSnippetKeepsWholeWordsAroundTheMatch() {
    let text = TextSearch.searchable("Checkout page: the modal has a drop shadow 2px too dark on the left edge")
    let snippet = MainWindowSearch.snippet(of: "Shadow", in: text, around: 12)
    #expect(snippet == "…has a drop shadow 2px too…")
}

@Test func mainWindowSearchSnippetHasNoEllipsisAtTheEnds() {
    #expect(MainWindowSearch.snippet(of: "shadow", in: "shadow", around: 12) == "shadow")
    #expect(MainWindowSearch.snippet(of: "remove", in: "remove shadow", around: 12) == "remove shadow")
}

@Test func mainWindowSearchSnippetIsNilWithoutAMatch() {
    #expect(MainWindowSearch.snippet(of: "invoice", in: "remove shadow") == nil)
    #expect(MainWindowSearch.snippet(of: "  ", in: "remove shadow") == nil)
}
