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
    #expect(try parse("text a.png") == .text(path: "a.png"))
    #expect(try parse("diff a.png b.png") == .diff(ShotCommand.DiffOptions(a: "a.png", b: "b.png")))
    #expect(try parse("diff --threshold 0 a.png b.png -o d.png") == .diff(ShotCommand.DiffOptions(a: "a.png", b: "b.png", output: "d.png", threshold: 0)))
    #expect(try parse("crop a.png --rect 10,20.5,300,40") == .crop(ShotCommand.CropOptions(input: "a.png", rect: [10, 20.5, 300, 40])))
    #expect(try parse("crop --rect=0,0,8,8 a.jpg -o b.jpg") == .crop(ShotCommand.CropOptions(input: "a.jpg", output: "b.jpg", rect: [0, 0, 8, 8])))
    #expect(try parse("capture --window Simulator") == .capture(AgentTarget(window: "Simulator")))
    #expect(try parse("capture --window=Calculator") == .capture(AgentTarget(window: "Calculator")))
    #expect(try parse("record --window Simulator") == .record(.start(AgentTarget(window: "Simulator"), duration: nil)))
    #expect(try parse("record --duration 1:30 --window Simulator") == .record(.start(AgentTarget(window: "Simulator"), duration: 90)))
    #expect(try parse("windows") == .windows)
    #expect(try parse("record --stop") == .record(.stop(id: nil)))
    #expect(try parse("record --stop ab12cd34") == .record(.stop(id: "ab12cd34")))
    #expect(try parse("record --status") == .record(.status))
    #expect(try parse("watch") == .watch(ShotCommand.WatchOptions()))
    #expect(try parse("watch --kind VIDEO --timeout 1:30") == .watch(ShotCommand.WatchOptions(kind: .video, timeout: 90)))
    #expect(try parse("watch --follow") == .watch(ShotCommand.WatchOptions(timeout: nil, follow: true)))
    #expect(try parse("watch --timeout 600 --follow") == .watch(ShotCommand.WatchOptions(timeout: 600, follow: true)))
    #expect(try parse("mcp") == .mcp)
    #expect(try parse("latest") == .latest(.image))
    #expect(try parse("latest --kind VIDEO") == .latest(.video))
    #expect(try parse("list") == .list(limit: nil, since: nil))
    #expect(try parse("list --limit 50 --since 2h") == .list(limit: 50, since: "2h"))
    #expect(try parse("get") == .get(nil))
    #expect(try parse("get /shots/a.png") == .get("/shots/a.png"))
    #expect(try parse("doctor") == .doctor)
    #expect(try parse("--version") == .version)
    #expect(try parse("-v") == .version)
}

@Test func flagsTakeTheirValuesEitherWayAndInAnyOrder() throws {
    let gif = try parse("gif --fps=15 a.mov -o out.gif --width 0 --start 1:02.5 --end=70")
    #expect(gif == .gif(ShotCommand.GIFOptions(input: "a.mov", output: "out.gif", fps: 15, width: 0, start: 62.5, end: 70)))
    let redact = try parse("redact a.png --rect 1,2,3,4 --style BLUR --rect=5,6,7,8 --output b.png")
    #expect(redact == .redact(ShotCommand.RedactOptions(input: "a.png", output: "b.png", rects: [[1, 2, 3, 4], [5, 6, 7, 8]], style: .blur)))
    #expect(try parse("redact a.png --detect email,TOKEN") == .redact(ShotCommand.RedactOptions(input: "a.png", detect: [.email, .token])))
    #expect(try parse("redact a.png --detect=card --rect 1,2,3,4") == .redact(ShotCommand.RedactOptions(input: "a.png", rects: [[1, 2, 3, 4]], detect: [.card])))
    #expect(try parse("annotate a.png --json -") == .annotate(ShotCommand.AnnotateOptions(input: "a.png", marks: .standardInput)))
}

@Test func captureAndRecordTakeABundleIDADisplayARectAndSwitches() throws {
    #expect(try parse("capture --bundle-id com.apple.iphonesimulator --no-shadow") == .capture(AgentTarget(bundleID: "com.apple.iphonesimulator", noShadow: true)))
    #expect(try parse("capture --bundle-id com.apple.Safari --window Apple --rect 0,0,800,120") == .capture(AgentTarget(window: "Apple", bundleID: "com.apple.Safari", rect: [0, 0, 800, 120])))
    #expect(try parse("capture --display 2 --wait-stable") == .capture(AgentTarget(display: 2, waitStable: 5)))
    #expect(try parse("capture --wait-stable=12 --window Simulator") == .capture(AgentTarget(window: "Simulator", waitStable: 12)))
    #expect(try parse("record --display 1 --rect 0,0,640,480 --duration 5") == .record(.start(AgentTarget(display: 1, rect: [0, 0, 640, 480]), duration: 5)))
    #expect(try parse("record --no-shadow --window Simulator") == .record(.start(AgentTarget(window: "Simulator", noShadow: true), duration: nil)))
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
    #expect(try parse("diff a.png -h") == .help("diff"))
    #expect(ShotCommand.usage("diff").hasPrefix("Usage: shot diff <a> <b> [-o out.png]"))
    #expect(try parse("crop a.png --help") == .help("crop"))
    #expect(ShotCommand.usage("crop").hasPrefix("Usage: shot crop <image> --rect x,y,w,h [-o out.png]"))
    #expect(ShotCommand.usage(nil).contains("shot crop <image>"))
    #expect(ShotCommand.usage("capture").hasPrefix("Usage: shot capture --window <title or app>"))
    #expect(try parse("text --help") == .help("text"))
    #expect(ShotCommand.usage(nil).contains("shot text <image>"))
    #expect(try parse("watch --follow -h") == .help("watch"))
    #expect(ShotCommand.usage("watch").hasPrefix("Usage: shot watch [--kind image|video|any] [--timeout 60] [--follow]"))
    #expect(try parse("windows --help") == .help("windows"))
    #expect(ShotCommand.usage(nil).contains("shot windows\n"))
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
    ("redact a.png", "redact", "needs at least one --rect x,y,width,height, or --detect email,token,card"),
    ("redact a.png --detect phone", "redact", "--detect phone must be email, token or card, or several split by commas, such as --detect email,token"),
    ("redact a.png --detect email --detect card", "redact", "--detect is given twice"),
    ("redact a.png --rect 1,2,0,4", "redact", "--rect 1,2,0,4 must be x,y,width,height in pixels, with a width and height above 0"),
    ("redact a.png --rect 1,2,3", "redact", "--rect 1,2,3 must be x,y,width,height in pixels, with a width and height above 0"),
    ("redact a.png --rect 1,2,3,4 --style smudge", "redact", "--style smudge must be blur or pixelate"),
    ("annotate a.png", "annotate", "needs --json with a file of marks, or - to read them from standard input"),
    ("mcp now", "mcp", "takes no arguments"),
    ("doctor --fix", "doctor", "takes no arguments"),
    ("latest a.png", "latest", "takes no file; use shot get to name one"),
    ("latest --kind gif", "latest", "--kind gif must be image, video or any"),
    ("list --limit 0", "list", "--limit 0 must be from 1 to 50"),
    ("list --limit 51", "list", "--limit 51 must be from 1 to 50"),
    ("list --since", "list", "--since needs a value"),
    ("get a b", "get", "expected one name or path, got 2; quote a name with spaces"),
    ("get a --kind image", "get", "unknown option --kind; get takes none"),
    ("frames a.mov --count 13", "frames", "--count 13 must be from 1 to 12"),
    ("frames a.mov --count 2 --every 1", "frames", "use --count or --every, not both"),
    ("frames a.mov --every 0", "frames", "--every 0 must be a time above 0, such as 2 or 0:30"),
    ("text", "text", "missing the file to work on"),
    ("text a.png -o b.json", "text", "unknown option -o; text takes none"),
    ("diff a.png", "diff", "needs two images, the one before and the one after; got 1"),
    ("diff a.png b.png c.png", "diff", "needs two images, the one before and the one after; got 3"),
    ("diff a.png b.png --threshold 2", "diff", "--threshold 2 must be a number from 0 to 1: how much of a colour's range a pixel may change by and still count as the same"),
    ("diff a.png b.png --fps 2", "diff", "unknown option --fps; it takes --threshold, -o"),
    ("crop a.png", "crop", "needs --rect x,y,width,height, the part to keep in the image's pixels"),
    ("crop --rect 1,2,3,4", "crop", "missing the file to work on"),
    ("crop a.png --rect 1,2,-3,4", "crop", "--rect 1,2,-3,4 must be x,y,width,height in pixels, with a width and height above 0"),
    ("crop a.png --rect 1,2,3,4 --rect 5,6,7,8", "crop", "--rect is given twice"),
    ("crop a.png --rect 1,2,3,4 --style blur", "crop", "unknown option --style; it takes --rect, -o"),
    ("capture", "capture", "needs --window with words from the window's title or app, such as --window Simulator, --bundle-id or --display"),
    ("capture --window", "capture", "--window needs a value"),
    ("capture a.png --window Simulator", "capture", "takes no file; name the window with --window"),
    ("capture --window a --window b", "capture", "--window is given twice"),
    ("capture --window a -o b.png", "capture", "unknown option -o; it takes --bundle-id, --display, --no-shadow, --rect, --wait-stable, --window"),
    ("capture --no-shadow", "capture", "needs --window with words from the window's title or app, such as --window Simulator, --bundle-id or --display"),
    ("capture --window a --no-shadow=yes", "capture", "--no-shadow takes no value"),
    ("capture --display 0", "capture", "--display 0 must be a display's number, from 1, as shot windows lists them"),
    ("capture --display main", "capture", "--display main must be a display's number, from 1, as shot windows lists them"),
    ("capture --display 1 --window a", "capture", "takes a window or a display, not both"),
    ("capture --display 1 --no-shadow", "capture", "can leave out only a window's shadow; a display has none"),
    ("capture --window a --rect 1,2,0,4", "capture", "--rect 1,2,0,4 must be x,y,width,height in points from the top-left corner, with a width and height above 0"),
    ("capture --window a --rect -1,2,3,4", "capture", "--rect -1,2,3,4 must be x,y,width,height in points from the top-left corner, with a width and height above 0"),
    ("capture --window a --wait-stable=0", "capture", "--wait-stable=0 must be a time above 0 and at most 30 seconds, such as --wait-stable=10"),
    ("capture --window a --wait-stable=31", "capture", "--wait-stable=31 must be a time above 0 and at most 30 seconds, such as --wait-stable=10"),
    ("windows now", "windows", "takes no arguments"),
    ("record --window a --wait-stable", "record", "unknown option --wait-stable; it takes --bundle-id, --display, --duration, --no-shadow, --rect, --window"),
    ("record", "record", "needs --window with words from the window's title or app, such as --window Simulator, --bundle-id or --display, or --mark, --stop or --status"),
    ("record --window a --duration 0", "record", "--duration 0 must be a time above 0 and at most 10 minutes, such as 10 or 1:30"),
    ("record --window a --duration 10:01", "record", "--duration 10:01 must be a time above 0 and at most 10 minutes, such as 10 or 1:30"),
    ("record --window a --stop", "record", "use --window, --mark, --stop or --status, one at a time"),
    ("record --stop a b", "record", "--stop takes at most a recording's id"),
    ("record --stop --status", "record", "--stop takes at most a recording's id"),
    ("record --status now", "record", "--status takes nothing else"),
    ("record --window a --fps 30", "record", "unknown option --fps; it takes --bundle-id, --display, --duration, --no-shadow, --rect, --window"),
    ("watch a.png", "watch", "takes no file; it watches Shot's capture folder"),
    ("watch --kind gif", "watch", "--kind gif must be image, video or any"),
    ("watch --timeout 0", "watch", "--timeout 0 must be a time above 0, such as 30 or 5:00"),
    ("watch --follow --follow", "watch", "--follow is given twice"),
    ("watch --window a", "watch", "unknown option --window; it takes --kind, --timeout"),
    ("record --window a --", "record", "-- needs a command after it, such as -- xcodebuild test"),
    ("record --window a --duration 5 -- make test", "record", "use --duration or a command, not both; with a command, the recording stops when it exits"),
    ("record -- make test", "record", "needs --window with words from the window's title or app, such as --window Simulator, --bundle-id or --display, or --mark, --stop or --status"),
    ("record --window a --mark b -- make", "record", "use --window, --mark, --stop or --status, one at a time"),
    ("record --mark", "record", "--mark needs a label, such as --mark \"tapped Login\""),
    ("record --mark a b c", "record", "--mark takes a label and at most a recording's id"),
    ("record --mark a --stop", "record", "--mark takes a label and at most a recording's id"),
] as [(String, String?, String)])
func aMistakeIsAUsageErrorThatSaysWhat(_ line: String, _ command: String?, _ message: String) throws {
    let error = try #require(usage(line))
    #expect(error.command == command)
    #expect(error.message == message)
}

@Test func recordRunsACommandWithEverythingAfterTheDoubleDashItsOwn() throws {
    #expect(try parse("record --window Simulator -- make test") == .record(.run(AgentTarget(window: "Simulator"), command: ["make", "test"])))
    // The command's own flags, --help and -- included, are never Shot's.
    let command = ["xcodebuild", "test", "--stop", "--help", "--", "-o", "x"]
    #expect(try ShotCommand.parse(["record", "--window", "Sim", "--"] + command) == .record(.run(AgentTarget(window: "Sim"), command: command)))
    #expect(try parse("record --help -- make") == .help("record"))
}

@Test func recordMarksTheRecordingInProgressOrOneByID() throws {
    #expect(try ShotCommand.parse(["record", "--mark", " tapped Login "]) == .record(.mark(label: "tapped Login", id: nil)))
    #expect(try ShotCommand.parse(["record", "--mark", "tapped Login", "ab12cd34"]) == .record(.mark(label: "tapped Login", id: "ab12cd34")))
    #expect(throws: ShotCommandError.usage("record", "--mark needs a label, such as --mark \"tapped Login\"")) {
        try ShotCommand.parse(["record", "--mark", "  "])
    }
    #expect(throws: ShotCommandError.usage("record", "--mark's label is over 200 characters")) {
        try ShotCommand.parse(["record", "--mark", String(repeating: "a", count: 201)])
    }
    #expect(ShotCommand.usage("record").contains("-- <command> [args…]] | --mark <label> [<id>]"))
}

@Test func aRecordedCommandExitsAsAShellWouldReportIt() {
    #expect(RecordedCommand.exitCode(waitStatus: 0) == (0, nil))
    #expect(RecordedCommand.exitCode(waitStatus: 3 << 8) == (3, nil))
    #expect(RecordedCommand.exitCode(waitStatus: 255 << 8) == (255, nil))
    #expect(RecordedCommand.exitCode(waitStatus: 2) == (130, 2))
    #expect(RecordedCommand.exitCode(waitStatus: 15) == (143, 15))
    // A core dump sets the bit above the signal.
    #expect(RecordedCommand.exitCode(waitStatus: 0x80 | 11) == (139, 11))
}

@Test func shotExitsWithTheCommandsCodeUnlessOnlyTheRecordingFailed() {
    #expect(RecordedCommand.exitCode(command: 0, recording: nil) == 0)
    #expect(RecordedCommand.exitCode(command: 3, recording: nil) == 3)
    #expect(RecordedCommand.exitCode(command: 3, recording: .io("lost")) == 3)
    #expect(RecordedCommand.exitCode(command: 0, recording: .noInput("discarded")) == 66)
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
