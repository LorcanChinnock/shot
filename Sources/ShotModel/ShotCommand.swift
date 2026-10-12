import Foundation

/// A `shot` command line, parsed: what to run and with what. Parsing is here, with no file access, so every flag is
/// tested on Linux; ShotCore's `ShotCommands` runs the media commands, and the MCP tools build the same values.
public enum ShotCommand: Equatable, Sendable {
    case info(path: String)
    case gif(GIFOptions)
    case trim(TrimOptions)
    case redact(RedactOptions)
    case annotate(AnnotateOptions)
    case frames(FramesOptions)
    /// A screenshot of the open window `window` names, taken by the running app.
    case capture(window: String)
    /// Starts, stops or asks about a recording of a window, made by the running app.
    case record(RecordAction)
    case mcp
    case version
    /// Usage, for one command or for all of them.
    case help(String?)

    public struct GIFOptions: Equatable, Sendable {
        public var input: String
        public var output: String?
        public var fps: Double
        /// The GIF's width in pixels; 0 keeps the video's.
        public var width: Int
        public var start: Double?
        public var end: Double?

        public init(input: String, output: String? = nil, fps: Double = 12, width: Int = 720, start: Double? = nil, end: Double? = nil) {
            self.input = input
            self.output = output
            self.fps = fps
            self.width = width
            self.start = start
            self.end = end
        }
    }

    public struct TrimOptions: Equatable, Sendable {
        public var input: String
        public var output: String?
        public var start: Double
        public var end: Double

        public init(input: String, output: String? = nil, start: Double, end: Double) {
            self.input = input
            self.output = output
            self.start = start
            self.end = end
        }
    }

    public enum RedactStyle: String, CaseIterable, Sendable {
        case blur, pixelate
    }

    public struct RedactOptions: Equatable, Sendable {
        public var input: String
        public var output: String?
        /// Each `[x, y, width, height]`, in the image's pixels.
        public var rects: [[Double]]
        public var style: RedactStyle

        public init(input: String, output: String? = nil, rects: [[Double]], style: RedactStyle = .pixelate) {
            self.input = input
            self.output = output
            self.rects = rects
            self.style = style
        }
    }

    /// Where `annotate`'s marks come from: a JSON file, standard input, or already read, as the MCP tool gives them.
    public enum Marks: Equatable, Sendable {
        case file(String)
        case standardInput
        case marks([CaptureMark])
    }

    public struct AnnotateOptions: Equatable, Sendable {
        public var input: String
        public var output: String?
        public var marks: Marks

        public init(input: String, output: String? = nil, marks: Marks) {
            self.input = input
            self.output = output
            self.marks = marks
        }
    }

    public struct FramesOptions: Equatable, Sendable {
        public static let maximumCount = 12
        /// The most `every` may give, so a short interval on a long video can't fill a disk.
        public static let maximumEvery = 60

        public var input: String
        /// The folder to write the frames into, which must not exist yet.
        public var output: String?
        /// How many frames to pick where the picture changes, 1 to `maximumCount`.
        public var count: Int
        /// Seconds between frames, taken evenly instead of where the picture changes.
        public var every: Double?
        /// The frames' width in pixels at most; they're never enlarged.
        public var width: Int

        public init(input: String, output: String? = nil, count: Int = 8, every: Double? = nil, width: Int = 1568) {
            self.input = input
            self.output = output
            self.count = count
            self.every = every
            self.width = width
        }
    }

    public enum RecordAction: Equatable, Sendable {
        /// Records `window`; with `duration`, waits for the recording to end.
        case start(window: String, duration: Double?)
        /// Stops the agent's recording `id`, or the one in progress.
        case stop(id: String?)
        case status
    }

    /// The commands `help` knows, in the order it lists them.
    public static let names = ["info", "gif", "trim", "redact", "annotate", "frames", "capture", "record", "mcp"]

    /// The command's name, for error messages such as `shot gif: …`.
    public var name: String {
        switch self {
        case .info: "info"
        case .gif: "gif"
        case .trim: "trim"
        case .redact: "redact"
        case .annotate: "annotate"
        case .frames: "frames"
        case .capture: "capture"
        case .record: "record"
        case .mcp: "mcp"
        case .version: "version"
        case .help: "help"
        }
    }

    // MARK: Parsing

    /// `arguments` without the program name. A mistake throws a `.usage` error naming the command it was for.
    public static func parse(_ arguments: [String]) throws(ShotCommandError) -> ShotCommand {
        guard let first = arguments.first else {
            throw .usage(nil, "missing a command")
        }
        let rest = Array(arguments.dropFirst())
        switch first {
        case "--version", "-v", "version":
            guard rest.isEmpty else { throw .usage(nil, "--version takes no arguments") }
            return .version
        case "--help", "-h", "help":
            guard rest.count <= 1 else { throw .usage(nil, "help takes at most one command") }
            if let command = rest.first, !names.contains(command) {
                throw .usage(nil, "no command named \"\(command)\"")
            }
            return .help(rest.first)
        case "mcp":
            if rest.contains(where: isHelp) { return .help("mcp") }
            guard rest.isEmpty else { throw .usage("mcp", "takes no arguments") }
            return .mcp
        case "info", "gif", "trim", "redact", "annotate", "frames":
            if rest.contains(where: isHelp) { return .help(first) }
            return try parseMedia(first, rest)
        case "capture":
            if rest.contains(where: isHelp) { return .help(first) }
            let (positional, values) = try options(first, rest)
            guard positional.isEmpty else { throw .usage(first, "takes no file; name the window with --window") }
            guard let window = values["window"]?.first?.trimmingCharacters(in: .whitespaces), !window.isEmpty else {
                throw .usage(first, "needs --window with words from the window's title or app, such as --window Simulator")
            }
            return .capture(window: window)
        case "record":
            if rest.contains(where: isHelp) { return .help(first) }
            return try parseRecord(rest)
        default:
            throw .usage(nil, "no command named \"\(first)\"")
        }
    }

    private static func isHelp(_ argument: String) -> Bool {
        argument == "--help" || argument == "-h"
    }

    /// The flags each command takes, and whether each can repeat; `-o` is `--output`.
    private static let flags: [String: [String: Bool]] = [
        "info": [:],
        "gif": ["output": false, "fps": false, "width": false, "start": false, "end": false],
        "trim": ["output": false, "start": false, "end": false],
        "redact": ["output": false, "rect": true, "style": false],
        "annotate": ["output": false, "json": false],
        "frames": ["output": false, "count": false, "every": false, "width": false],
        "capture": ["window": false],
        "record": ["window": false, "duration": false],
    ]

    /// `record --window … [--duration s]`, `record --stop [id]` or `record --status`.
    private static func parseRecord(_ arguments: [String]) throws(ShotCommandError) -> ShotCommand {
        if arguments.first == "--status" {
            guard arguments.count == 1 else { throw .usage("record", "--status takes nothing else") }
            return .record(.status)
        }
        if arguments.first == "--stop" {
            let rest = arguments.dropFirst()
            guard rest.count <= 1, !(rest.first?.hasPrefix("-") ?? false) else {
                throw .usage("record", "--stop takes at most a recording's id")
            }
            return .record(.stop(id: rest.first))
        }
        if arguments.contains("--stop") || arguments.contains("--status") {
            throw .usage("record", "use --window, --stop or --status, one at a time")
        }
        let (positional, values) = try options("record", arguments)
        guard positional.isEmpty else { throw .usage("record", "takes no file; name the window with --window") }
        guard let window = values["window"]?.first?.trimmingCharacters(in: .whitespaces), !window.isEmpty else {
            throw .usage("record", "needs --window with words from the window's title or app, such as --window Simulator, or --stop or --status")
        }
        var duration: Double?
        if let text = values["duration"]?.first {
            guard let seconds = Self.seconds(text), seconds > 0, seconds <= AgentRequest.maximumDuration else {
                throw .usage("record", "--duration \(text) must be a time above 0 and at most \(Int(AgentRequest.maximumDuration / 60)) minutes, such as 10 or 1:30")
            }
            duration = seconds
        }
        return .record(.start(window: window, duration: duration))
    }

    /// The arguments that aren't flags, and each flag's values, checked against what `command` takes.
    private static func options(_ command: String, _ arguments: [String]) throws(ShotCommandError) -> (positional: [String], values: [String: [String]]) {
        let allowed = flags[command] ?? [:]
        var positional: [String] = []
        var values: [String: [String]] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            guard argument.hasPrefix("-"), argument != "-" else {
                positional.append(argument)
                continue
            }
            var name = argument.drop { $0 == "-" }.description
            var value: String?
            if let equals = name.firstIndex(of: "=") {
                value = String(name[name.index(after: equals)...])
                name = String(name[..<equals])
            }
            if argument == "-o" {
                name = "output"
            }
            guard let repeats = allowed[name], argument.hasPrefix("--") || argument == "-o" else {
                let known = allowed.keys.map { $0 == "output" ? "-o" : "--\($0)" }.sorted()
                throw .usage(command, "unknown option \(argument)" + (known.isEmpty ? "; \(command) takes none" : "; it takes \(known.joined(separator: ", "))"))
            }
            if value == nil {
                guard index < arguments.count else { throw .usage(command, "\(argument) needs a value") }
                value = arguments[index]
                index += 1
            }
            if !repeats, values[name] != nil {
                throw .usage(command, "\(name == "output" ? "-o" : "--\(name)") is given twice")
            }
            values[name, default: []].append(value ?? "")
        }
        return (positional, values)
    }

    private static func parseMedia(_ command: String, _ arguments: [String]) throws(ShotCommandError) -> ShotCommand {
        let (positional, values) = try options(command, arguments)
        guard positional.count == 1, let input = positional.first else {
            throw .usage(command, positional.isEmpty ? "missing the file to work on" : "expected one file, got \(positional.count)")
        }
        let output = values["output"]?.first
        func time(_ name: String) throws(ShotCommandError) -> Double? {
            guard let text = values[name]?.first else { return nil }
            guard let seconds = Self.seconds(text) else {
                throw .usage(command, "--\(name) \(text) isn't a time; use seconds such as 2.5, or m:ss such as 1:02.5")
            }
            return seconds
        }
        switch command {
        case "info":
            return .info(path: input)
        case "gif":
            var options = GIFOptions(input: input, output: output, start: try time("start"), end: try time("end"))
            if let text = values["fps"]?.first {
                guard let fps = Double(text), fps.isFinite, (1...30).contains(fps) else {
                    throw .usage(command, "--fps \(text) must be a number from 1 to 30")
                }
                options.fps = fps
            }
            if let text = values["width"]?.first {
                guard let width = Int(text), width == 0 || (16...8192).contains(width) else {
                    throw .usage(command, "--width \(text) must be from 16 to 8192 pixels, or 0 for the video's own width")
                }
                options.width = width
            }
            if let start = options.start, let end = options.end, end <= start {
                throw .usage(command, "--end must be after --start")
            }
            return .gif(options)
        case "trim":
            guard let start = try time("start"), let end = try time("end") else {
                throw .usage(command, "needs both --start and --end")
            }
            guard end > start else { throw .usage(command, "--end must be after --start") }
            return .trim(TrimOptions(input: input, output: output, start: start, end: end))
        case "redact":
            let rects = try (values["rect"] ?? []).map { (text: String) throws(ShotCommandError) -> [Double] in
                guard let rect = Self.rect(text) else {
                    throw .usage(command, "--rect \(text) must be x,y,width,height in pixels, with a width and height above 0")
                }
                return rect
            }
            guard !rects.isEmpty else { throw .usage(command, "needs at least one --rect x,y,width,height") }
            var style = RedactStyle.pixelate
            if let text = values["style"]?.first {
                guard let picked = RedactStyle(rawValue: text.lowercased()) else {
                    throw .usage(command, "--style \(text) must be blur or pixelate")
                }
                style = picked
            }
            return .redact(RedactOptions(input: input, output: output, rects: rects, style: style))
        case "frames":
            var options = FramesOptions(input: input, output: output)
            if let text = values["count"]?.first {
                guard let count = Int(text), (1...FramesOptions.maximumCount).contains(count) else {
                    throw .usage(command, "--count \(text) must be from 1 to \(FramesOptions.maximumCount)")
                }
                options.count = count
            }
            if let text = values["every"]?.first {
                guard values["count"] == nil else { throw .usage(command, "use --count or --every, not both") }
                guard let every = Self.seconds(text), every > 0 else {
                    throw .usage(command, "--every \(text) must be a time above 0, such as 2 or 0:30")
                }
                options.every = every
            }
            if let text = values["width"]?.first {
                guard let width = Int(text), (16...8192).contains(width) else {
                    throw .usage(command, "--width \(text) must be from 16 to 8192 pixels")
                }
                options.width = width
            }
            return .frames(options)
        default:
            guard let json = values["json"]?.first else {
                throw .usage(command, "needs --json with a file of marks, or - to read them from standard input")
            }
            return .annotate(AnnotateOptions(input: input, output: output, marks: json == "-" ? .standardInput : .file(json)))
        }
    }

    /// Seconds from `2.5`, `1:02.5` or `1:02:03`; `nil` for anything else, or below zero.
    static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count), let last = Double(parts[parts.count - 1]), last.isFinite, last >= 0 else {
            return nil
        }
        var total = last
        for (place, part) in parts.dropLast().reversed().enumerated() {
            guard let whole = Int(part), whole >= 0, parts.count == 1 || last < 60 else { return nil }
            total += Double(whole) * (place == 0 ? 60 : 3600)
        }
        return total
    }

    /// `[x, y, width, height]` from `x,y,w,h`, with a positive width and height.
    static func rect(_ text: String) -> [Double]? {
        let values = text.split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4, values.allSatisfy({ $0?.isFinite == true }) else {
            return nil
        }
        let rect = values.compactMap { $0 }
        return rect[2] > 0 && rect[3] > 0 ? rect : nil
    }

    // MARK: Help

    /// What `shot help` prints, or `shot help <command>`.
    public static func usage(_ command: String?, program: String = "shot") -> String {
        let lines: [String: String] = [
            "info": "\(program) info <file>\n    An image's size and scale or a video's size and length, and the record Shot keeps inside a capture.",
            "gif": "\(program) gif <video> [-o out.gif] [--fps 12] [--width 720] [--start 2.5] [--end 9]\n    A GIF of the video, or of part of it. --width 0 keeps the video's width; GIFs stop at 60 seconds.",
            "trim": "\(program) trim <video> --start 2.5 --end 9 [-o out.mov]\n    The part of the video between two times, without re-encoding where it can.",
            "redact": "\(program) redact <image> --rect x,y,w,h [--rect …] [--style blur|pixelate] [-o out.png]\n    Hides each rectangle, in the image's pixels. Pixelate is the default.",
            "annotate": "\(program) annotate <image> --json marks.json [-o out.png]\n    Draws marks on the image, in the format of Shot's capture record. --json - reads them from standard input.\n    A mark: {\"type\": \"arrow\", \"from\": [410, 220], \"to\": [612, 388], \"color\": \"red\"}\n    Every type and field: \(docs)#using-shot-with-ai-agents",
            "frames": "\(program) frames <video> [--count 8 | --every 2] [--width 1568] [-o folder]\n    Still frames of the video, for an agent that can't watch it: where the picture changes, or evenly every few seconds.",
            "capture": "\(program) capture --window <title or app>\n    A screenshot of that open window, taken by Shot without taking focus, saved to the capture folder. Opens Shot in the background if it isn't running; needs Settings › Agents › Let agents capture and record on.",
            "record": "\(program) record --window <title or app> [--duration 10] | --stop [<id>] | --status\n    Records that open window through Shot, without its microphone or camera, for at most \(Int(AgentRequest.maximumDuration / 60)) minutes, saved to the capture folder. Without --duration it prints an id and returns at once; --stop ends it. Opens Shot in the background if it isn't running; needs Settings › Agents › Let agents capture and record on.",
            "mcp": "\(program) mcp\n    Serves Shot's captures to an AI agent over MCP, on standard input and output.",
        ]
        if let command, let line = lines[command] {
            return "Usage: " + line
        }
        return """
        Usage: \(program) <command> [options]

        \(names.compactMap { lines[$0] }.joined(separator: "\n"))
        \(program) --version
            The version, settings and capture folder.

        Without -o, the output goes beside the input as the next version, such as "name (2).png". Nothing is ever
        overwritten. Results are JSON on standard output; errors go to standard error with an exit code for each kind:
        64 a wrong option, 65 a file or marks Shot can't use, 66 no such file, window or recording, 69 Shot isn't
        answering agents, 70 an internal error, 73 the output can't be made, 74 reading or writing failed, 75 Shot is
        busy, 77 no Screen Recording permission. More: \(docs)#the-shot-command-line
        """
    }

    /// The online docs, which render `docs/usage.md`.
    static let docs = "https://shot.lorcanchinnock.com/docs/"

    /// `value` as `shot` prints it: pretty, with keys sorted, so it reads and diffs well.
    public static func json(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// Why a `shot` command failed, and the exit code it ends with, following `sysexits.h`.
public enum ShotCommandError: Error, Equatable, Sendable {
    /// A bad flag, a missing argument or a value out of range; the command it was for, if any.
    case usage(String?, String)
    /// Not an image or video Shot can read, marks that don't make sense, or a rect off the image.
    case data(String)
    /// The input file isn't there.
    case noInput(String)
    /// The output can't be made: it exists, or its folder doesn't or isn't writable.
    case cantCreate(String)
    /// Reading or writing failed partway.
    case io(String)
    case `internal`(String)
    /// Shot isn't running, or Let agents capture and record is off, so nothing answers.
    case unavailable(String)
    /// Shot is in the middle of something it can't share: a selection, the recording setup, or a recording.
    case busy(String)
    /// Shot doesn't have the Screen Recording permission.
    case noPermission(String)

    public var exitCode: Int32 {
        switch self {
        case .usage: 64
        case .data: 65
        case .noInput: 66
        case .unavailable: 69
        case .internal: 70
        case .cantCreate: 73
        case .io: 74
        case .busy: 75
        case .noPermission: 77
        }
    }

    public var message: String {
        switch self {
        case let .usage(_, message), let .data(message), let .noInput(message), let .cantCreate(message), let .io(message), let .internal(message),
             let .unavailable(message), let .busy(message), let .noPermission(message):
            message
        }
    }

    /// The error with `exitCode`, as the app sends it back to the command line; an unknown code is `.internal`.
    public init(exitCode: Int32, message: String) {
        self = switch exitCode {
        case 64: .usage(nil, message)
        case 65: .data(message)
        case 66: .noInput(message)
        case 69: .unavailable(message)
        case 73: .cantCreate(message)
        case 74: .io(message)
        case 75: .busy(message)
        case 77: .noPermission(message)
        default: .internal(message)
        }
    }
}

extension CaptureMark {
    /// Marks as `shot annotate` and the MCP `annotate` tool take them: a JSON array of marks, or an object with an
    /// `annotations` array, such as a whole capture record. Each is checked, and the first problem names its mark.
    public static func list(from data: Data) throws(ShotCommandError) -> [CaptureMark] {
        struct Wrapped: Decodable {
            var annotations: [CaptureMark]
        }
        let decoder = JSONDecoder()
        let marks: [CaptureMark]
        do {
            // Decided by the first character, so a mistake in an array is reported as one.
            if data.first(where: { !" \t\r\n".utf8.contains($0) }) == UInt8(ascii: "[") {
                marks = try decoder.decode([CaptureMark].self, from: data)
            } else {
                marks = try decoder.decode(Wrapped.self, from: data).annotations
            }
        } catch {
            throw .data("the marks aren't a JSON array of marks or an object with an \"annotations\" array: \(Self.reason(error))")
        }
        for (index, mark) in marks.enumerated() {
            if let problem = mark.problem {
                throw .data("mark \(index) (\(mark.type)): \(problem)")
            }
        }
        return marks
    }

    private static func reason(_ error: Error) -> String {
        switch error as? DecodingError {
        case let .keyNotFound(key, context)?:
            "\(Self.path(context.codingPath + [key])) is missing"
        case let .typeMismatch(_, context)?, let .valueNotFound(_, context)?, let .dataCorrupted(context)?:
            "\(Self.path(context.codingPath)): \(context.debugDescription)"
        default:
            error.localizedDescription
        }
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().drop { $0 == "." }.description
    }

    /// The types a mark can have.
    public static let types: Set<String> = [
        "arrow", "line", "rectangle", "rounded", "ellipse", "triangle", "diamond", "star", "highlight", "blur", "pixelate",
        "spotlight", "text", "counter", "note", "pen", "marker", "image",
    ]

    /// The palette names `color` can be, in the palette's order.
    public static let paletteNames = ["red", "orange", "yellow", "green", "blue", "black", "white"]
    /// The palette names `color` can be.
    public static let colorNames = Set(paletteNames)

    /// What's wrong with this mark for drawing it, or `nil` when it can be drawn.
    public var problem: String? {
        func isPoint(_ p: [Double]?) -> Bool { p?.count == 2 && p?.allSatisfy(\.isFinite) == true }
        func isRect(_ r: [Double]?) -> Bool { r?.count == 4 && r?.allSatisfy(\.isFinite) == true && (r?[2] ?? -1) >= 0 && (r?[3] ?? -1) >= 0 }
        guard Self.types.contains(type) else {
            return "unknown type; use one of \(Self.types.sorted().joined(separator: ", "))"
        }
        if let color, !Self.colorNames.contains(color.lowercased()) {
            return "unknown color \"\(color)\"; use one of \(Self.colorNames.sorted().joined(separator: ", ")), or put a colour such as #FF3B30 in hex instead"
        }
        for (name, value) in [("hex", hex), ("fill", fill)] {
            if let value, HexColor.components(value) == nil {
                return "\(name) \"\(value)\" isn't a colour such as #FF3B30"
            }
        }
        switch type {
        case "image":
            return "a placed image can't be drawn from a record, which doesn't hold its pixels"
        case "arrow", "line":
            return isPoint(from) && isPoint(to) ? nil : "needs from and to, each [x, y]"
        case "counter":
            return isPoint(center) ? nil : "needs center, as [x, y]"
        case "text", "note":
            guard let text, !text.isEmpty else { return "needs text" }
            return isRect(rect) ? nil : "needs rect, as [x, y, width, height]; a text starts at its x and y"
        case "pen", "marker":
            guard let points, !points.isEmpty else { return "needs points, as [[x, y], …]" }
            return points.allSatisfy(isPoint) ? nil : "every point must be [x, y]"
        default:
            return isRect(rect) ? nil : "needs rect, as [x, y, width, height]"
        }
    }
}
