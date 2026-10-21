import Foundation
import Testing
@testable import ShotCore

private func parse(_ json: String) throws(ShotCommandError) -> VideoEdit {
    try VideoEdit.parse(Data(json.utf8))
}

/// The message of the error `json` gives, or nil if it parses.
private func problem(_ json: String) -> String? {
    do {
        _ = try parse(json)
        return nil
    } catch {
        guard case let .data(message) = error else { return "not a data error: \(error)" }
        return message
    }
}

@Test func everyFieldOfAVideoEditParses() throws {
    let edit = try parse("""
    {
      "keep": [[1, "0:02.5"], [4, 9]],
      "speed": 2,
      "mute": true,
      "crop": [0, 0, 640, 360],
      "marks": [{"start": 3, "end": "0:06", "type": "arrow", "from": [1, 2], "to": [3, 4], "color": "red"}, {"start": 1, "type": "counter", "center": [5, 5]}],
      "append": ["other.mov"],
      "format": "GIF",
      "maxBytes": 10000000,
      "fps": 10,
      "width": 480
    }
    """)
    #expect(edit == VideoEdit(
        keep: [[1, 2.5], [4, 9]], speed: 2, mute: true, crop: [0, 0, 640, 360],
        marks: [
            VideoEdit.TimedMark(start: 3, end: 6, mark: CaptureMark(type: "arrow", from: [1, 2], to: [3, 4], color: "red")),
            VideoEdit.TimedMark(start: 1, end: 4, mark: CaptureMark(type: "counter", center: [5, 5])),
        ],
        append: ["other.mov"], format: .gif, maxBytes: 10_000_000, fps: 10, width: 480
    ))
    #expect(try parse(#"{"cut": [[0, 1]], "mute": false}"#) == VideoEdit(cut: [[0, 1]]))
}

@Test(arguments: [
    ("[]", "the edit must be a JSON object with any of keep, cut, speed, mute, crop, marks, append, format, maxBytes, fps or width"),
    ("{}", "the edit changes nothing; give at least one of keep, cut, speed, mute, crop, marks, append, format, maxBytes, fps or width"),
    (#"{"trim": [0, 1]}"#, #"unknown field "trim"; a video edit takes keep, cut, speed, mute, crop, marks, append, format, maxBytes, fps or width"#),
    (#"{"keep": [[0, 1]], "cut": [[2, 3]]}"#, "use keep or cut, not both"),
    (#"{"keep": []}"#, "keep must be an array of [start, end] in seconds, such as [[2, 9.5]]"),
    (#"{"keep": [[0, 1, 2]]}"#, #"keep[0] must be [start, end] in seconds, such as [2, 9.5] or ["0:02", "1:10"]"#),
    (#"{"keep": [[0, 5], [4, 6]]}"#, "keep[1] starts before keep[0] ends; give the parts in order, without overlaps"),
    (#"{"cut": [[3, 3]]}"#, "cut[0] must end after it starts"),
    (#"{"cut": [[-1, 3]]}"#, #"cut[0] must be [start, end] in seconds, such as [2, 9.5] or ["0:02", "1:10"]"#),
    (#"{"speed": 10}"#, "speed must be a number from 0.25 to 4, such as 2 for twice as fast"),
    (#"{"mute": "yes"}"#, "mute must be true or false"),
    (#"{"crop": [0, 0, 0, 10]}"#, "crop must be [x, y, width, height] in the video's pixels, with a width and height above 0"),
    (#"{"marks": [{"type": "arrow", "from": [1, 1], "to": [2, 2]}]}"#, "marks[0] needs start, the second it shows from"),
    (#"{"marks": [{"start": 4, "end": 2, "type": "arrow", "from": [1, 1], "to": [2, 2]}]}"#, "marks[0].end must be seconds after its start"),
    (#"{"marks": [{"start": "soon", "type": "counter", "center": [1, 1]}]}"#, #"marks[0].start must be seconds, such as 2.5, or m:ss, such as "1:02.5""#),
    (#"{"marks": [{"start": 1, "type": "arrow", "from": [1, 1]}]}"#, "marks[0] (arrow): needs from and to, each [x, y]"),
    (#"{"append": [""]}"#, "append[0] must name a video"),
    (#"{"format": "webm"}"#, "format must be mp4, mov or gif"),
    (#"{"maxBytes": 5}"#, "maxBytes must be a whole number of bytes, at least 10000, such as 10000000 for 10 MB"),
    (#"{"maxBytes": 12000.5}"#, "maxBytes must be a whole number of bytes, at least 10000, such as 10000000 for 10 MB"),
    (#"{"fps": 60, "format": "gif"}"#, "fps must be a number from 1 to 30"),
    (#"{"width": 8, "format": "gif"}"#, "width must be from 16 to 8192 pixels, or 0 for the video's own width"),
    (#"{"fps": 10}"#, #"fps is for a GIF; add "format": "gif""#),
    (#"{"width": 480, "format": "mp4"}"#, #"width is for a GIF; add "format": "gif""#),
])
func aBadVideoEditNamesTheFieldThatsWrong(_ json: String, _ message: String) {
    #expect(problem(json) == message)
}

@Test func keepTakesOutEverythingAroundAndBetweenItsParts() throws {
    let keep = VideoEdit(keep: [[1, 2], [4, 20]])
    #expect(try keep.removed(from: 10) == [0..<1, 2..<4])
    #expect(try VideoEdit(keep: [[0, 10]]).removed(from: 10) == [])
    #expect(throws: ShotCommandError.data("keep[1] starts at 12 s, past the end of the 10.00 s video")) { try VideoEdit(keep: [[1, 2], [12, 13]]).removed(from: 10) }
}

@Test func cutsAreMergedSortedAndKeptWithinTheVideo() throws {
    let cut = VideoEdit(cut: [[6, 12], [1, 3], [2, 4]])
    #expect(try cut.removed(from: 10) == [1..<4, 6..<10])
    #expect(throws: ShotCommandError.data("cut[0] starts at 10 s, past the end of the 10.00 s video")) { try VideoEdit(cut: [[10, 11]]).removed(from: 10) }
}

@Test func aTimeMovesEarlierByWhatsRemovedBeforeIt() {
    let removed: [Range<Double>] = [1..<4, 6..<8]
    #expect(VideoEdit.time(0.5, after: removed) == 0.5)
    #expect(VideoEdit.time(2, after: removed) == 1)
    #expect(VideoEdit.time(5, after: removed) == 2)
    #expect(VideoEdit.time(7, after: removed) == 3)
    #expect(VideoEdit.time(9, after: removed) == 4)
}

@Test func aGIFLowersItsFrameRateBeforeItsWidth() {
    let steps = SizeFit.gifSteps(fps: 12, width: 720)
    #expect(steps.prefix(5) == [12, 10, 8, 6].map { SizeFit.GIFStep(fps: $0, width: 720) } + [SizeFit.GIFStep(fps: 12, width: 640)])
    #expect(steps.last == SizeFit.GIFStep(fps: 6, width: 320))
    // A GIF already narrow keeps its width and only slows down.
    #expect(SizeFit.gifSteps(fps: 8, width: 300) == [SizeFit.GIFStep(fps: 8, width: 300), SizeFit.GIFStep(fps: 6, width: 300)])
}

@Test func aStepFitsWhenItsCorrectedEstimateLeavesATenthSpare() {
    #expect(SizeFit.fits(estimate: 89, ratio: 1, within: 100))
    #expect(!SizeFit.fits(estimate: 95, ratio: 1, within: 100))
    // A step written came out at 1.5 times its estimate, so the next is taken to as well.
    #expect(SizeFit.fits(estimate: 50, ratio: 1.5, within: 100))
    #expect(!SizeFit.fits(estimate: 50, ratio: 2, within: 100))
}

@Test func theToolsOwnArgumentsCanBeIgnoredInAVideoEdit() throws {
    let arguments: JSONValue = .object(["name": .string("rec"), "mute": .bool(true)])
    #expect(try VideoEdit.parse(arguments, ignoring: ["path", "name"]) == VideoEdit(mute: true))
}
