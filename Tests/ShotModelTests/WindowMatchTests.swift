import Foundation
import Testing
@testable import ShotModel

/// Front to back.
private let windows = [
    WindowMatch.Candidate(id: 1, app: "Xcode", title: "Shot — CaptureCoordinator.swift"),
    WindowMatch.Candidate(id: 2, app: "Simulator", title: "iPhone 17 Pro"),
    WindowMatch.Candidate(id: 3, app: "Safari", title: "Simulator docs"),
    WindowMatch.Candidate(id: 4, app: "Calculator", title: ""),
    WindowMatch.Candidate(id: 5, app: "Café Notes", title: "Résumé"),
    WindowMatch.Candidate(id: 6, app: "Safari", title: "Apple"),
]

private func best(_ query: String) -> UInt32? {
    WindowMatch.best(query, in: windows)?.id
}

@Test func anExactTitleBeatsAnAppNameAndAnAppNameBeatsATitleContainingIt() {
    #expect(best("Simulator docs") == 3)
    // Safari's "Simulator docs" contains it, but Simulator is the app's whole name.
    #expect(best("simulator") == 2)
    #expect(best("iphone 17 pro") == 2)
}

@Test func aTitleContainingTheQueryBeatsAnAppContainingIt() {
    #expect(best("17") == 2)
    #expect(best("calc") == 4)
    #expect(best("coordinator") == 1)
}

@Test func everyWordCanBeAnywhereInTheAppAndTitle() {
    #expect(best("safari apple") == 6)
    #expect(best("xcode capturecoordinator") == 1)
    #expect(best("safari banana") == nil)
}

@Test func matchingIgnoresCaseAccentsAndExtraSpaces() {
    #expect(best("CAFE NOTES") == 5)
    #expect(best("resume") == 5)
    #expect(best("  iPhone   17  ") == 2)
}

@Test func equalMatchesGoToTheFrontmost() {
    #expect(best("safari") == 3)
    let twins = [WindowMatch.Candidate(id: 9, app: "Notes", title: "A"), WindowMatch.Candidate(id: 8, app: "Notes", title: "B")]
    #expect(WindowMatch.best("notes", in: twins)?.id == 9)
}

@Test func nothingMatchesAnEmptyQueryOrAMissingWindow() {
    #expect(best("") == nil)
    #expect(best("   ") == nil)
    #expect(best("Photoshop") == nil)
    #expect(WindowMatch.best("anything", in: []) == nil)
}

@Test func theListingNamesUpToTenWindows() {
    let many = (1...12).map { WindowMatch.Candidate(id: UInt32($0), app: "App \($0)", title: $0 == 1 ? "" : "Window \($0)") }
    let listing = WindowMatch.listing(many)
    #expect(listing.hasPrefix("Open windows, front to back:\n  App 1\n  App 2 — Window 2\n"))
    #expect(listing.contains("App 10 — Window 10"))
    #expect(!listing.contains("App 11"))
    #expect(listing.hasSuffix("  and 2 more"))
    #expect(WindowMatch.listing([]) == "No other app has a window open on screen.")
}
