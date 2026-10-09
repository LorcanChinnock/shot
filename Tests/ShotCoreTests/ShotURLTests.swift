import Foundation
import Testing
@testable import ShotCore

private let home = FileManager.default.homeDirectoryForCurrentUser

@Test(arguments: [
    ("shot://capture-area", ShotURL.action(.captureArea)),
    ("shot://capture-fullscreen", .action(.captureFullscreen)),
    ("shot://capture-window", .action(.captureWindow)),
    ("shot://record", .action(.record)),
    ("shot://record-fullscreen", .action(.recordFullscreen)),
    ("shot://record-window", .action(.recordWindow)),
    ("shot://record?full=1", .action(.recordFullscreen)),
    ("shot://record?full=0", .action(.record)),
    ("shot://pause", .pause),
    ("shot://gallery", .gallery),
    ("shot://settings", .settings(section: nil)),
    ("shot://settings?section=gallery", .settings(section: "gallery")),
    ("shot://settings?section=shortcuts", .settings(section: "shortcuts")),
    ("shot://annotate?path=/tmp/a.png", .edit(.image(URL(fileURLWithPath: "/tmp/a.png")))),
    ("shot://annotate?path=/tmp/a.mov", .edit(.video(URL(fileURLWithPath: "/tmp/a.mov")))),
    ("shot://edit-video?path=/tmp/a.png", .edit(.video(URL(fileURLWithPath: "/tmp/a.png")))),
    ("shot://annotate?path=~/My%20Shot.png", .edit(.image(home.appendingPathComponent("My Shot.png")))),
])
func everyShotURLHasARoute(_ string: String, _ expected: ShotURL) throws {
    let url = try #require(URL(string: string))
    #expect(try ShotURL(url) == expected)
}

@Test func everyActionHasAURL() throws {
    for action in ShotAction.allCases {
        let url = try #require(URL(string: "shot://\(action.rawValue)"))
        #expect(try ShotURL(url) == .action(action))
    }
}

@Test(arguments: [
    ("shot://annotate", ShotURL.ParseError.missingPath(host: "annotate")),
    ("shot://edit-video?path=", .missingPath(host: "edit-video")),
    ("shot://capture", .unknownHost("capture")),
    ("https://capture-area", .notShot),
])
func aBadShotURLSaysWhy(_ string: String, _ expected: ShotURL.ParseError) throws {
    let url = try #require(URL(string: string))
    #expect(throws: expected) {
        try ShotURL(url)
    }
}

@Test func aBadShotURLsMessageNamesTheHost() {
    #expect(ShotURL.ParseError.missingPath(host: "annotate").localizedDescription == "Missing path for annotate")
    #expect(ShotURL.ParseError.unknownHost("capture").localizedDescription == "Unknown action: capture")
}
