import Foundation
import Testing
@testable import ShotCore

private let home = FileManager.default.homeDirectoryForCurrentUser

@Test(arguments: [
    ("shot://capture-area", ShotURL.action(.captureArea)),
    ("shot://capture-fullscreen", .action(.captureFullscreen)),
    ("shot://capture-window", .action(.captureWindow)),
    ("shot://capture-previous", .action(.capturePrevious)),
    ("shot://record", .action(.record)),
    ("shot://record-fullscreen", .action(.recordFullscreen)),
    ("shot://record-window", .action(.recordWindow)),
    ("shot://record?full=1", .action(.recordFullscreen)),
    ("shot://record?full=0", .action(.record)),
    ("shot://capture-timer", .captureTimer(seconds: 5)),
    ("shot://capture-timer?seconds=3", .captureTimer(seconds: 3)),
    ("shot://capture-timer?seconds=60", .captureTimer(seconds: 60)),
    ("shot://pause", .pause),
    ("shot://gallery", .gallery),
    ("shot://settings", .settings(section: nil)),
    ("shot://settings?section=gallery", .settings(section: "gallery")),
    ("shot://settings?section=shortcuts", .settings(section: "shortcuts")),
    ("shot://welcome", .welcome),
    ("shot://annotate?path=/tmp/a.png", .edit(.image(URL(fileURLWithPath: "/tmp/a.png")))),
    ("shot://annotate?path=/tmp/a.mov", .edit(.video(URL(fileURLWithPath: "/tmp/a.mov")))),
    ("shot://edit-video?path=/tmp/a.png", .edit(.video(URL(fileURLWithPath: "/tmp/a.png")))),
    ("shot://annotate?path=~/My%20Shot.png", .edit(.image(home.appendingPathComponent("My Shot.png")))),
    ("shot-dev://gallery", .gallery),
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
    ("shot://capture-timer?seconds=0", .invalidSeconds("0")),
    ("shot://capture-timer?seconds=61", .invalidSeconds("61")),
    ("shot://capture-timer?seconds=soon", .invalidSeconds("soon")),
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

@Test func aBadTimerURLsMessageSaysWhatIsAllowed() {
    #expect(ShotURL.ParseError.invalidSeconds("soon").localizedDescription == "Seconds must be a whole number from 1 to 60, not soon")
}
