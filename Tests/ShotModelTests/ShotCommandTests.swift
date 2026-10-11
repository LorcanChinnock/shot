import Foundation
import Testing
@testable import ShotModel

private func parse(_ line: String) throws(ShotCommandError) -> ShotCommand {
    try ShotCommand.parse(line.split(separator: " ").map(String.init))
}

/// The usage error `line` gives: the command it names and the message.
private func usage(_ line: String) -> (command: String?, message: String)? {
    do {
        _ = try parse(line)
        return nil
    } catch {
        guard case let .usage(command, message) = error else { return nil }
        return (command, message)
    }
}

@Test func everyCommandParsesWithItsDefaults() throws {
    #expect(try parse("info a.png") == .info(path: "a.png"))
    #expect(try parse("gif a.mov") == .gif(ShotCommand.GIFOptions(input: "a.mov")))
    #expect(try parse("trim a.mov --start 1 --end 2") == .trim(ShotCommand.TrimOptions(input: "a.mov", start: 1, end: 2)))
    #expect(try parse("redact a.png --rect 1,2,3,4") == .redact(ShotCommand.RedactOptions(input: "a.png", rects: [[1, 2, 3, 4]])))
    #expect(try parse("annotate a.png --json m.json") == .annotate(ShotCommand.AnnotateOptions(input: "a.png", marks: .file("m.json"))))
    #expect(try parse("frames a.mov") == .frames(ShotCommand.FramesOptions(input: "a.mov")))
    #expect(try parse("frames a.mov --every 0:30 --width 800 -o out") == .frames(ShotCommand.FramesOptions(input: "a.mov", output: "out", every: 30, width: 800)))
    #expect(try parse("frames a.mov --count 3") == .frames(ShotCommand.FramesOptions(input: "a.mov", count: 3)))
    #expect(try parse("capture --window Simulator") == .capture(window: "Simulator"))
    #expect(try parse("capture --window=Calculator") == .capture(window: "Calculator"))
    #expect(try parse("record --window Simulator") == .record(.start(window: "Simulator", duration: nil)))
    #expect(try parse("record --duration 1:30 --window Simulator") == .record(.start(window: "Simulator", duration: 90)))
    #expect(try parse("record --stop") == .record(.stop(id: nil)))
    #expect(try parse("record --stop ab12cd34") == .record(.stop(id: "ab12cd34")))
    #expect(try parse("record --status") == .record(.status))
    #expect(try parse("mcp") == .mcp)
    #expect(try parse("--version") == .version)
    #expect(try parse("-v") == .version)
}

@Test func flagsTakeTheirValuesEitherWayAndInAnyOrder() throws {
    let gif = try parse("gif --fps=15 a.mov -o out.gif --width 0 --start 1:02.5 --end=70")
    #expect(gif == .gif(ShotCommand.GIFOptions(input: "a.mov", output: "out.gif", fps: 15, width: 0, start: 62.5, end: 70)))
    let redact = try parse("redact a.png --rect 1,2,3,4 --style BLUR --rect=5,6,7,8 --output b.png")
    #expect(redact == .redact(ShotCommand.RedactOptions(input: "a.png", output: "b.png", rects: [[1, 2, 3, 4], [5, 6, 7, 8]], style: .blur)))
    #expect(try parse("annotate a.png --json -") == .annotate(ShotCommand.AnnotateOptions(input: "a.png", marks: .standardInput)))
}

@Test func helpComesFromAnyCommand() throws {
    #expect(try parse("help") == .help(nil))
    #expect(try parse("--help") == .help(nil))
    #expect(try parse("help gif") == .help("gif"))
    #expect(try parse("trim --help") == .help("trim"))
    #expect(try parse("redact a.png -h") == .help("redact"))
    #expect(ShotCommand.usage("trim").hasPrefix("Usage: shot trim <video> --start"))
    #expect(ShotCommand.usage(nil, program: "shot-cli").contains("shot-cli annotate <image> --json"))
    #expect(try parse("capture --help") == .help("capture"))
    #expect(ShotCommand.usage("capture").hasPrefix("Usage: shot capture --window <title or app>"))
}

@Test(arguments: [
    ("", nil, "missing a command"),
    ("frobnicate", nil, #"no command named "frobnicate""#),
    ("help nope", nil, #"no command named "nope""#),
    ("gif", "gif", "missing the file to work on"),
    ("gif a.mov b.mov", "gif", "expected one file, got 2"),
    ("gif a.mov --speed 2", "gif", "unknown option --speed; it takes --end, --fps, --start, --width, -o"),
    ("info a.png -o b", "info", "unknown option -o; info takes none"),
    ("gif a.mov --fps", "gif", "--fps needs a value"),
    ("gif a.mov --fps 0", "gif", "--fps 0 must be a number from 1 to 30"),
    ("gif a.mov --width 8", "gif", "--width 8 must be from 16 to 8192 pixels, or 0 for the video's own width"),
    ("gif a.mov --start 5 --end 2", "gif", "--end must be after --start"),
    ("gif a.mov -o a.gif -o b.gif", "gif", "-o is given twice"),
    ("trim a.mov --start 1", "trim", "needs both --start and --end"),
    ("trim a.mov --start soon --end 2", "trim", "--start soon isn't a time; use seconds such as 2.5, or m:ss such as 1:02.5"),
    ("redact a.png", "redact", "needs at least one --rect x,y,width,height"),
    ("redact a.png --rect 1,2,0,4", "redact", "--rect 1,2,0,4 must be x,y,width,height in pixels, with a width and height above 0"),
    ("redact a.png --rect 1,2,3", "redact", "--rect 1,2,3 must be x,y,width,height in pixels, with a width and height above 0"),
    ("redact a.png --rect 1,2,3,4 --style smudge", "redact", "--style smudge must be blur or pixelate"),
    ("annotate a.png", "annotate", "needs --json with a file of marks, or - to read them from standard input"),
    ("mcp now", "mcp", "mcp takes no arguments"),
    ("frames a.mov --count 13", "frames", "--count 13 must be from 1 to 12"),
    ("frames a.mov --count 2 --every 1", "frames", "use --count or --every, not both"),
    ("frames a.mov --every 0", "frames", "--every 0 must be a time above 0, such as 2 or 0:30"),
    ("capture", "capture", "needs --window with words from the window's title or app, such as --window Simulator"),
    ("capture --window", "capture", "--window needs a value"),
    ("capture a.png --window Simulator", "capture", "takes no file; name the window with --window"),
    ("capture --window a --window b", "capture", "--window is given twice"),
    ("capture --window a -o b.png", "capture", "unknown option -o; it takes --window"),
    ("record", "record", "needs --window with words from the window's title or app, such as --window Simulator, or --stop or --status"),
    ("record --window a --duration 0", "record", "--duration 0 must be a time above 0 and at most 10 minutes, such as 10 or 1:30"),
    ("record --window a --duration 10:01", "record", "--duration 10:01 must be a time above 0 and at most 10 minutes, such as 10 or 1:30"),
    ("record --window a --stop", "record", "use --window, --stop or --status, one at a time"),
    ("record --stop a b", "record", "--stop takes at most a recording's id"),
    ("record --stop --status", "record", "--stop takes at most a recording's id"),
    ("record --status now", "record", "--status takes nothing else"),
    ("record --window a --fps 30", "record", "unknown option --fps; it takes --duration, --window"),
] as [(String, String?, String)])
func aMistakeIsAUsageErrorThatSaysWhat(_ line: String, _ command: String?, _ message: String) throws {
    let error = try #require(usage(line))
    #expect(error.command == command)
    #expect(error.message == message)
}

@Test func timesReadAsSecondsOrClockTime() {
    #expect(ShotCommand.seconds("2.5") == 2.5)
    #expect(ShotCommand.seconds("0") == 0)
    #expect(ShotCommand.seconds("1:02.5") == 62.5)
    #expect(ShotCommand.seconds("1:00:03") == 3603)
    for bad in ["", "-1", "1:75", "a:10", "1::2", "inf", "nan", "1:2:3:4"] {
        #expect(ShotCommand.seconds(bad) == nil, "\(bad)")
    }
}

@Test func eachErrorHasItsExitCode() {
    #expect(ShotCommandError.usage(nil, "").exitCode == 64)
    #expect(ShotCommandError.data("").exitCode == 65)
    #expect(ShotCommandError.noInput("").exitCode == 66)
    #expect(ShotCommandError.internal("").exitCode == 70)
    #expect(ShotCommandError.cantCreate("").exitCode == 73)
    #expect(ShotCommandError.io("").exitCode == 74)
    #expect(ShotCommandError.unavailable("").exitCode == 69)
    #expect(ShotCommandError.busy("").exitCode == 75)
    #expect(ShotCommandError.noPermission("").exitCode == 77)
    #expect(ShotCommandError.cantCreate("it exists").message == "it exists")
    #expect(ShotCommandError.busy("recording").message == "recording")
}

@Test func anErrorComesBackFromItsExitCode() {
    let errors: [ShotCommandError] = [
        .usage(nil, "a"), .data("b"), .noInput("c"), .unavailable("d"), .internal("e"), .cantCreate("f"), .io("g"), .busy("h"), .noPermission("i"),
    ]
    for error in errors {
        #expect(ShotCommandError(exitCode: error.exitCode, message: error.message) == error)
    }
    #expect(ShotCommandError(exitCode: 1, message: "odd") == .internal("odd"))
}

@Test func marksComeAsAnArrayOrInsideARecord() throws {
    let array = try CaptureMark.list(from: Data(#"[{"type":"arrow","from":[1,2],"to":[3,4],"color":"Red"}]"#.utf8))
    #expect(array == [CaptureMark(type: "arrow", from: [1, 2], to: [3, 4], color: "Red")])
    let wrapped = try CaptureMark.list(from: Data(#"{"schema":"shot.capture/2","annotations":[{"type":"counter","center":[5,5]}]}"#.utf8))
    #expect(wrapped == [CaptureMark(type: "counter", center: [5, 5])])
    #expect(try CaptureMark.list(from: Data("[]".utf8)).isEmpty)
}

@Test(arguments: [
    ("not json", "the marks aren't a JSON array of marks or an object with an \"annotations\" array"),
    (#"{"marks":[]}"#, "annotations is missing"),
    (#"[{"rect":[1,2,3,4]}]"#, "[0].type is missing"),
    (#"[{"type":"squiggle"}]"#, "mark 0 (squiggle): unknown type"),
    (#"[{"type":"arrow","from":[1,2]}]"#, "mark 0 (arrow): needs from and to, each [x, y]"),
    (#"[{"type":"counter","center":[1,2]},{"type":"rectangle","rect":[1,2,-3,4]}]"#, "mark 1 (rectangle): needs rect, as [x, y, width, height]"),
    (#"[{"type":"text","rect":[1,2,3,4]}]"#, "mark 0 (text): needs text"),
    (#"[{"type":"pen","points":[[1,2],[3]]}]"#, "mark 0 (pen): every point must be [x, y]"),
    (#"[{"type":"image","rect":[1,2,3,4]}]"#, "mark 0 (image): a placed image can't be drawn"),
    (#"[{"type":"ellipse","rect":[1,2,3,4],"color":"mauve"}]"#, #"mark 0 (ellipse): unknown color "mauve""#),
    (##"[{"type":"ellipse","rect":[1,2,3,4],"hex":"#12"}]"##, ##"mark 0 (ellipse): hex "#12" isn't a colour"##),
])
func badMarksAreDataErrorsThatNameTheMark(_ json: String, _ message: String) throws {
    do {
        _ = try CaptureMark.list(from: Data(json.utf8))
        Issue.record("\(json) was accepted")
    } catch {
        #expect(error.exitCode == 65)
        #expect(error.message.contains(message), "\(error.message)")
    }
}

@Test func outputIsPrettyJSONWithSortedKeys() {
    #expect(ShotCommand.json(.object(["path": .string("/a/b.png"), "bytes": .number(10)])) == "{\n  \"bytes\" : 10,\n  \"path\" : \"/a/b.png\"\n}")
}
