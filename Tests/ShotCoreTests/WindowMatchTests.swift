import Foundation
import Testing
@testable import ShotCore

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

private let apps = [
    WindowMatch.Candidate(id: 1, app: "Safari", title: "Apple", bundleID: "com.apple.Safari", width: 1200, height: 800),
    WindowMatch.Candidate(id: 2, app: "Simulator", title: "iPhone 17 Pro", bundleID: "com.apple.iphonesimulator", width: 402, height: 874),
    WindowMatch.Candidate(id: 3, app: "Safari", title: "Swift docs", bundleID: "com.apple.Safari", width: 1200, height: 800),
]

@Test func aBundleIDNamesItsAppsFrontWindowOrNarrowsTheWords() {
    #expect(WindowMatch.best("", bundleID: "com.apple.Safari", in: apps)?.id == 1)
    #expect(WindowMatch.best("", bundleID: "COM.APPLE.IPHONESIMULATOR", in: apps)?.id == 2)
    #expect(WindowMatch.best("docs", bundleID: "com.apple.Safari", in: apps)?.id == 3)
    #expect(WindowMatch.best("iphone", bundleID: "com.apple.Safari", in: apps) == nil)
    #expect(WindowMatch.best("", bundleID: "com.example.missing", in: apps) == nil)
    #expect(WindowMatch.best("", in: apps) == nil)
}

@Test func aQueryCanBeTheWholeBundleID() {
    #expect(WindowMatch.best("com.apple.iphonesimulator", in: apps)?.id == 2)
    // Part of one is just words, so it can't pick an app by accident.
    #expect(WindowMatch.best("com.apple", in: apps) == nil)
}

@Test func theWindowsListSaysWhichIsFrontmost() {
    let json = WindowMatch.json(apps, frontmostBundleID: "com.apple.Safari")
    guard case let .array(windows) = json else {
        Issue.record("not an array")
        return
    }
    #expect(windows.map { $0["frontmost"] } == [.bool(true), .bool(false), .bool(false)])
    #expect(windows[1]["bundleID"] == .string("com.apple.iphonesimulator"))
    #expect(windows[1]["size"] == .object(["width": .number(402), "height": .number(874)]))
    #expect(windows[1]["title"] == .string("iPhone 17 Pro"))
    let none = WindowMatch.json(apps, frontmostBundleID: "com.apple.Terminal")
    guard case let .array(unfocused) = none else { return }
    #expect(unfocused.allSatisfy { $0["frontmost"] == .bool(false) })
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
