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
    /// The text in an image, read on the device, with each line's and word's box.
    case text(path: String)
    case diff(DiffOptions)
    /// A part of an image at full resolution, written as its next version.
    case crop(CropOptions)
    /// The image or video editor's changes, from one JSON edit, written as a new file beside it.
    case edit(EditOptions)
    /// A screenshot of an open window or a display, taken by the running app.
    case capture(AgentTarget)
    /// Starts, stops or asks about a recording of a window, made by the running app.
    case record(RecordAction)
    /// Waits for the user's next capture, or with `follow`, reports each one as it comes.
    case watch(WatchOptions)
    /// Asks the person to pick an area, window or display on the running app's overlay, and saves what they pick.
    case pick(PickOptions)
    /// The open windows and displays, as the running app sees them.
    case windows
    /// The newest capture of a kind, as `latest_capture` gives it.
    case latest(AgentCaptures.Kind)
    /// Recent captures, as `list_captures` gives them.
    case list(limit: Int?, since: String?, query: String? = nil)
    /// The capture a name or path names, or the newest, as `get_capture` gives it.
    case get(String?)
    /// Checks what agents need and says how to fix what's wrong.
    case doctor
    case mcp
    /// Reads the text of the screenshots in a folder into the app's text index. The app runs it in the background, in a
    /// process of its own, so Vision's memory never stays in the app; it isn't in `help`.
    case indexText(folder: String)
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
        /// The kinds of private text to find in the image and hide as well, from `--detect`.
        public var detect: Set<SensitiveText.Kind>
        public var style: RedactStyle

        public init(input: String, output: String? = nil, rects: [[Double]] = [], detect: Set<SensitiveText.Kind> = [], style: RedactStyle = .pixelate) {
            self.input = input
            self.output = output
            self.rects = rects
            self.detect = detect
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

    public struct WatchOptions: Equatable, Sendable {
        /// How long `watch` waits without `--timeout`.
        public static let defaultTimeout: Double = 60

        public var kind: AgentCaptures.Kind
        /// Seconds to wait; with `follow`, nil runs until interrupted.
        public var timeout: Double?
        /// Keep going after the first capture, printing each as it comes.
        public var follow: Bool

        public init(kind: AgentCaptures.Kind = .any, timeout: Double? = defaultTimeout, follow: Bool = false) {
            self.kind = kind
            self.timeout = timeout
            self.follow = follow
        }
    }

    public struct PickOptions: Equatable, Sendable {
        /// How long `pick` waits for the person without `--timeout`.
        public static let defaultTimeout: Double = 60

        /// What the overlay asks the person to select.
        public var prompt: String?
        /// Seconds to wait for the person before the overlay closes.
        public var timeout: Double

        public init(prompt: String? = nil, timeout: Double = defaultTimeout) {
            self.prompt = prompt
            self.timeout = timeout
        }
    }

    public struct DiffOptions: Equatable, Sendable {
        /// The image before.
        public var a: String
        /// The image after, whose size and pixels the result is in, and beside which the diff image goes.
        public var b: String
        public var output: String?
        /// How much a channel may differ, from 0 to 1 of its range, before a pixel counts as changed.
        public var threshold: Double

        public init(a: String, b: String, output: String? = nil, threshold: Double = ImageDiff.defaultThreshold) {
            self.a = a
            self.b = b
            self.output = output
            self.threshold = threshold
        }
    }

    public struct CropOptions: Equatable, Sendable {
        public var input: String
        public var output: String?
        /// `[x, y, width, height]`, in the image's pixels from the top left.
        public var rect: [Double]

        public init(input: String, output: String? = nil, rect: [Double]) {
            self.input = input
            self.output = output
            self.rect = rect
        }
    }

    /// Where `edit`'s spec comes from: a JSON file, standard input, the JSON itself, or already read, as the MCP tools
    /// give it. Read from JSON, it's an image's or a video's edit by what the input is.
    public enum Spec: Equatable, Sendable {
        case file(String)
        case standardInput
        case json(String)
        case edit(ImageEdit)
        case video(VideoEdit)
    }

    public struct EditOptions: Equatable, Sendable {
        public var input: String
        public var output: String?
        public var spec: Spec

        public init(input: String, output: String? = nil, spec: Spec) {
            self.input = input
            self.output = output
            self.spec = spec
        }
    }

    public enum RecordAction: Equatable, Sendable {
        /// Records the target; with `duration`, waits for the recording to end.
        case start(AgentTarget, duration: Double?)
        /// Stops the agent's recording `id`, or the one in progress.
        case stop(id: String?)
        case status
        /// Records the target while `command` runs, and stops when it exits.
        case run(AgentTarget, command: [String])
        /// Stamps `label` on the agent's recording `id`, or the one in progress.
        case mark(label: String, id: String?)
    }

    /// The commands `help` knows, in the order it lists them.
    public static let names = ["info", "gif", "trim", "redact", "annotate", "frames", "text", "diff", "crop", "edit", "latest", "list", "get", "windows", "capture", "record", "watch", "pick", "doctor", "mcp"]

    /// The command's name, for error messages such as `shot gif: …`.
    public var name: String {
        switch self {
        case .info: "info"
        case .gif: "gif"
        case .trim: "trim"
        case .redact: "redact"
        case .annotate: "annotate"
        case .frames: "frames"
        case .text: "text"
        case .diff: "diff"
        case .crop: "crop"
        case .edit: "edit"
        case .capture: "capture"
        case .record: "record"
        case .watch: "watch"
        case .pick: "pick"
        case .windows: "windows"
        case .latest: "latest"
        case .list: "list"
        case .get: "get"
        case .doctor: "doctor"
        case .mcp: "mcp"
        case .indexText: "index-text"
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
        case "mcp", "doctor":
            if rest.contains(where: isHelp) { return .help(first) }
            guard rest.isEmpty else { throw .usage(first, "takes no arguments") }
            return first == "mcp" ? .mcp : .doctor
        case "latest", "list", "get":
            if rest.contains(where: isHelp) { return .help(first) }
            return try parseCaptures(first, rest)
        case "index-text":
            guard rest.count == 1, let folder = rest.first else { throw .usage(first, "expected one folder") }
            return .indexText(folder: folder)
        case "info", "gif", "trim", "redact", "annotate", "frames", "text", "crop", "edit":
            if rest.contains(where: isHelp) { return .help(first) }
            return try parseMedia(first, rest)
        case "diff":
            if rest.contains(where: isHelp) { return .help(first) }
            return try parseDiff(rest)
        case "capture":
            if rest.contains(where: isHelp) { return .help(first) }
            let (positional, values) = try options(first, rest)
            guard positional.isEmpty else { throw .usage(first, "takes no file; name the window with --window") }
            return .capture(try target(first, values))
        case "record":
            // What follows -- is the command's own, its --help included.
            if rest.prefix(while: { $0 != "--" }).contains(where: isHelp) { return .help(first) }
            return try parseRecord(rest)
        case "watch":
            if rest.contains(where: isHelp) { return .help(first) }
            return try parseWatch(rest)
        case "pick":
            if rest.contains(where: isHelp) { return .help(first) }
            return try parsePick(rest)
        case "windows":
            if rest.contains(where: isHelp) { return .help(first) }
            guard rest.isEmpty else { throw .usage(first, "takes no arguments") }
            return .windows
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
        "redact": ["output": false, "rect": true, "detect": false, "style": false],
        "annotate": ["output": false, "json": false],
        "frames": ["output": false, "count": false, "every": false, "width": false],
        "text": [:],
        "diff": ["output": false, "threshold": false],
        "crop": ["output": false, "rect": false],
        "edit": ["output": false, "json": false],
        "capture": ["window": false, "bundle-id": false, "display": false, "rect": false, "no-shadow": false, "wait-stable": false],
        "record": ["window": false, "bundle-id": false, "display": false, "rect": false, "no-shadow": false, "duration": false],
        "watch": ["kind": false, "timeout": false],
        "pick": ["prompt": false, "timeout": false],
        "latest": ["kind": false],
        "list": ["limit": false, "since": false, "query": false],
        "get": [:],
    ]
    /// Flags that take no value, or one only after `=`, such as `--wait-stable=10`.
    private static let switches: Set<String> = ["no-shadow", "wait-stable"]

    /// What `capture` or `record` is pointed at, from `--window`, `--bundle-id`, `--display`, `--rect`, `--no-shadow`
    /// and `--wait-stable`.
    private static func target(_ command: String, _ values: [String: [String]]) throws(ShotCommandError) -> AgentTarget {
        func text(_ name: String) -> String? {
            values[name]?.first.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        var target = AgentTarget(window: text("window"), bundleID: text("bundle-id"), noShadow: values["no-shadow"] != nil)
        guard target.window != nil || target.bundleID != nil || values["display"] != nil else {
            let others = command == "record" ? ", --bundle-id or --display, or --mark, --stop or --status" : ", --bundle-id or --display"
            throw .usage(command, "needs --window with words from the window's title or app, such as --window Simulator\(others)")
        }
        if values["no-shadow"]?.first?.isEmpty == false {
            throw .usage(command, "--no-shadow takes no value")
        }
        if let text = values["display"]?.first {
            guard let display = Int(text), display >= 1 else {
                throw .usage(command, "--display \(text) must be a display's number, from 1, as shot windows lists them")
            }
            target.display = display
        }
        if let text = values["rect"]?.first {
            guard let rect = Self.rect(text), AgentTarget.isRect(rect) else {
                throw .usage(command, "--rect \(text) must be x,y,width,height in points from the top-left corner, with a width and height above 0")
            }
            target.rect = rect
        }
        if let text = values["wait-stable"]?.first {
            let seconds = text.isEmpty ? AgentTarget.defaultWaitStable : Self.seconds(text)
            guard let seconds, seconds > 0, seconds <= AgentTarget.maximumWaitStable else {
                throw .usage(command, "--wait-stable=\(text) must be a time above 0 and at most \(Int(AgentTarget.maximumWaitStable)) seconds, such as --wait-stable=10")
            }
            target.waitStable = seconds
        }
        if let problem = target.problem {
            throw .usage(command, problem)
        }
        return target
    }

    /// `watch [--kind image|video|any] [--timeout 60] [--follow]`.
    private static func parseWatch(_ arguments: [String]) throws(ShotCommandError) -> ShotCommand {
        let follow = arguments.contains("--follow")
        if arguments.filter({ $0 == "--follow" }).count > 1 {
            throw .usage("watch", "--follow is given twice")
        }
        let (positional, values) = try options("watch", arguments.filter { $0 != "--follow" })
        guard positional.isEmpty else { throw .usage("watch", "takes no file; it watches Shot's capture folder") }
        var options = WatchOptions(timeout: follow ? nil : WatchOptions.defaultTimeout, follow: follow)
        if let text = values["kind"]?.first {
            guard let kind = AgentCaptures.Kind(rawValue: text.lowercased()) else {
                throw .usage("watch", "--kind \(text) must be image, video or any")
            }
            options.kind = kind
        }
        if let text = values["timeout"]?.first {
            guard let seconds = Self.seconds(text), seconds > 0 else {
                throw .usage("watch", "--timeout \(text) must be a time above 0, such as 30 or 5:00")
            }
            options.timeout = seconds
        }
        return .watch(options)
    }

    /// `pick [--prompt "Select the broken toolbar"] [--timeout 60]`.
    private static func parsePick(_ arguments: [String]) throws(ShotCommandError) -> ShotCommand {
        let (positional, values) = try options("pick", arguments)
        guard positional.isEmpty else { throw .usage("pick", "takes no file; put what to select in --prompt") }
        var options = PickOptions()
        if let text = values["prompt"]?.first {
            guard text.count <= AgentRequest.maximumPrompt else {
                throw .usage("pick", "--prompt can be at most \(AgentRequest.maximumPrompt) characters")
            }
            options.prompt = AgentRequest.cleanPrompt(text)
        }
        if let text = values["timeout"]?.first {
            guard let seconds = Self.seconds(text), seconds > 0, seconds <= AgentRequest.maximumDuration else {
                throw .usage("pick", "--timeout \(text) must be a time above 0 and at most \(Int(AgentRequest.maximumDuration / 60)) minutes, such as 30 or 2:00")
            }
            options.timeout = seconds
        }
        return .pick(options)
    }

    /// `latest [--kind image|video|any]`, `list [--limit n] [--since when] [--query words]` or `get [<name or path>]`, which read the
    /// capture folder as the MCP tools do.
    private static func parseCaptures(_ command: String, _ arguments: [String]) throws(ShotCommandError) -> ShotCommand {
        let (positional, values) = try options(command, arguments)
        switch command {
        case "get":
            guard positional.count <= 1 else {
                throw .usage(command, "expected one name or path, got \(positional.count); quote a name with spaces")
            }
            return .get(positional.first)
        case "latest":
            guard positional.isEmpty else { throw .usage(command, "takes no file; use shot get to name one") }
            guard let text = values["kind"]?.first else {
                return .latest(.image)
            }
            guard let kind = AgentCaptures.Kind(rawValue: text.lowercased()) else {
                throw .usage(command, "--kind \(text) must be image, video or any")
            }
            return .latest(kind)
        default:
            guard positional.isEmpty else { throw .usage(command, "takes no file; use shot get to name one") }
            var limit: Int?
            if let text = values["limit"]?.first {
                guard let number = Int(text), (1...AgentCaptures.maximumLimit).contains(number) else {
                    throw .usage(command, "--limit \(text) must be from 1 to \(AgentCaptures.maximumLimit)")
                }
                limit = number
            }
            return .list(limit: limit, since: values["since"]?.first, query: values["query"]?.first)
        }
    }

    /// `record --window … [--duration s | -- command …]`, `record --mark label [id]`, `record --stop [id]` or
    /// `record --status`.
    private static func parseRecord(_ arguments: [String]) throws(ShotCommandError) -> ShotCommand {
        if arguments.first == "--mark" {
            let rest = arguments.dropFirst()
            guard let label = rest.first?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
                throw .usage("record", "--mark needs a label, such as --mark \"tapped Login\"")
            }
            guard label.count <= RecordingMark.maximumLabel else {
                throw .usage("record", "--mark's label is over \(RecordingMark.maximumLabel) characters")
            }
            guard rest.count <= 2, !(rest.dropFirst().first?.hasPrefix("-") ?? false) else {
                throw .usage("record", "--mark takes a label and at most a recording's id")
            }
            return .record(.mark(label: label, id: rest.dropFirst().first))
        }
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
        let split = arguments.firstIndex(of: "--")
        let own = split.map { Array(arguments[..<$0]) } ?? arguments
        if own.contains("--stop") || own.contains("--status") || own.contains("--mark") {
            throw .usage("record", "use --window, --mark, --stop or --status, one at a time")
        }
        let (positional, values) = try options("record", own)
        guard positional.isEmpty else { throw .usage("record", "takes no file; name the window with --window") }
        let picked = try target("record", values)
        if let split {
            let command = Array(arguments[(split + 1)...])
            guard !command.isEmpty else { throw .usage("record", "-- needs a command after it, such as -- xcodebuild test") }
            guard values["duration"] == nil else {
                throw .usage("record", "use --duration or a command, not both; with a command, the recording stops when it exits")
            }
            return .record(.run(picked, command: command))
        }
        var duration: Double?
        if let text = values["duration"]?.first {
            guard let seconds = Self.seconds(text), seconds > 0, seconds <= AgentRequest.maximumDuration else {
                throw .usage("record", "--duration \(text) must be a time above 0 and at most \(Int(AgentRequest.maximumDuration / 60)) minutes, such as 10 or 1:30")
            }
            duration = seconds
        }
        return .record(.start(picked, duration: duration))
    }

    /// `diff <a> <b> [-o out.png] [--threshold 0.1]`.
    private static func parseDiff(_ arguments: [String]) throws(ShotCommandError) -> ShotCommand {
        let (positional, values) = try options("diff", arguments)
        guard positional.count == 2 else {
            throw .usage("diff", "needs two images, the one before and the one after; got \(positional.count)")
        }
        var options = DiffOptions(a: positional[0], b: positional[1], output: values["output"]?.first)
        if let text = values["threshold"]?.first {
            guard let threshold = Double(text), threshold.isFinite, (0 ... 1).contains(threshold) else {
                throw .usage("diff", "--threshold \(text) must be a number from 0 to 1: how much of a colour's range a pixel may change by and still count as the same")
            }
            options.threshold = threshold
        }
        return .diff(options)
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
            if value == nil, switches.contains(name) {
                value = ""
            } else if value == nil {
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
        case "text":
            return .text(path: input)
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
            var detect: Set<SensitiveText.Kind> = []
            if let text = values["detect"]?.first {
                guard let kinds = SensitiveText.Kind.list(text) else {
                    throw .usage(command, "--detect \(text) must be email, token or card, or several split by commas, such as --detect email,token")
                }
                detect = kinds
            }
            guard !rects.isEmpty || !detect.isEmpty else { throw .usage(command, "needs at least one --rect x,y,width,height, or --detect email,token,card") }
            var style = RedactStyle.pixelate
            if let text = values["style"]?.first {
                guard let picked = RedactStyle(rawValue: text.lowercased()) else {
                    throw .usage(command, "--style \(text) must be blur or pixelate")
                }
                style = picked
            }
            return .redact(RedactOptions(input: input, output: output, rects: rects, detect: detect, style: style))
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
        case "crop":
            guard let text = values["rect"]?.first else {
                throw .usage(command, "needs --rect x,y,width,height, the part to keep in the image's pixels")
            }
            guard let rect = Self.rect(text) else {
                throw .usage(command, "--rect \(text) must be x,y,width,height in pixels, with a width and height above 0")
            }
            return .crop(CropOptions(input: input, output: output, rect: rect))
        case "edit":
            guard let json = values["json"]?.first else {
                throw .usage(command, "needs --json with a file holding the edit, - to read it from standard input, or the edit itself, such as --json '{\"crop\": [0, 0, 800, 600]}'")
            }
            let spec: Spec = if json == "-" {
                .standardInput
            } else if json.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
                .json(json)
            } else {
                .file(json)
            }
            return .edit(EditOptions(input: input, output: output, spec: spec))
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
            "redact": "\(program) redact <image> [--rect x,y,w,h …] [--detect email,token,card] [--style blur|pixelate] [-o out.png]\n    Hides each rectangle, in the image's pixels. --detect reads the text on this Mac and hides each email, token or API key, and card number of the kinds named; found lists their kinds and boxes, never their text. If there's nothing to hide, no file is written and path is the input. Pixelate is the default.",
            "annotate": "\(program) annotate <image> --json marks.json [-o out.png]\n    Draws marks on the image, in the format of Shot's capture record. --json - reads them from standard input.\n    A mark: {\"type\": \"arrow\", \"from\": [410, 220], \"to\": [612, 388], \"color\": \"red\"}\n    Every type and field: \(docs)#using-shot-with-ai-agents",
            "frames": "\(program) frames <video> [--count 8 | --every 2] [--width 1568] [-o folder]\n    Still frames of the video, for an agent that can't watch it: where the picture changes, or evenly every few seconds.",
            "text": "\(program) text <image>\n    The text in the image, read on this Mac: each line and word with its box, [x, y, width, height] in the image's pixels from the top left.",
            "diff": "\(program) diff <a> <b> [-o out.png] [--threshold 0.1]\n    Where image b differs from a: a dimmed copy of b with the changes highlighted and boxed, and the boxes in b's pixels.\n    Images of different sizes are compared at b's size. --threshold 0 counts any difference; 0.1, the default, ignores anti-aliasing.",
            "crop": "\(program) crop <image> --rect x,y,w,h [-o out.png]\n    Keeps that part of the image at full resolution, in the image's pixels from the top left, as a new version that opens in Shot with the crop still adjustable.",
            "edit": "\(program) edit <image or video> --json edit.json [-o out]\n    Makes the editors' changes as a new file that opens in Shot with its layers live. An image takes crop, pad and background, style (shadow, border, corners), marks, layers to remove by id, other images to place, scale to 1x, and format. A video takes keep or cut, speed, mute, crop, timed marks, videos to append, format (mp4, mov or gif) and maxBytes. --json - reads the edit from standard input, and --json '{…}' takes it as it is.\n    An image edit: {\"pad\": 40, \"background\": \"white\", \"style\": {\"shadow\": \"soft\", \"corners\": 12}, \"marks\": [{\"type\": \"arrow\", \"from\": [410, 220], \"to\": [612, 388]}]}\n    A video edit: {\"keep\": [[2, 9.5]], \"speed\": 2, \"marks\": [{\"start\": 3, \"end\": 6, \"type\": \"arrow\", \"from\": [410, 220], \"to\": [612, 388]}], \"format\": \"gif\", \"maxBytes\": 10000000}\n    Every field: \(docs)#editing-images and \(docs)#editing-videos",
            "latest": "\(program) latest [--kind image|video|any]\n    The newest capture, a screenshot unless --kind says otherwise: its name, path, kind, when it was taken, and what Shot recorded in it, as latest_capture gives it.",
            "list": "\(program) list [--limit 10] [--since 2h] [--query words]\n    Recent captures, newest first, as list_captures gives them. --since takes a date such as 2026-10-10 or a span back from now such as 10m, 2h or 3d. --query keeps those whose name or screenshot text contains the words, ignoring case and accents, with the lines that match; Shot reads screenshots' text in the background while it runs.",
            "get": "\(program) get [<name or path>]\n    The capture a file name, words from it or its path names, or the newest of any kind, as get_capture gives it.",
            "windows": "\(program) windows\n    The open windows, front to back, with each one's app, bundle ID, title and size and which is frontmost, and the displays. Needs Settings › Agents › Let agents capture and record on.",
            "capture": "\(program) capture --window <title or app> | --bundle-id <id> | --display <n> [--rect x,y,w,h] [--no-shadow] [--wait-stable[=5]]\n    A screenshot of that open window or whole display, taken by Shot without taking focus, saved to the capture folder. --bundle-id picks the app's front window, or with --window one of its windows. --rect keeps that part, in points from the top-left corner. --wait-stable waits, up to 5 seconds or the time given, for the picture to stop changing. Opens Shot in the background if it isn't running; needs Settings › Agents › Let agents capture and record on.",
            "record": "\(program) record --window <title or app> | --bundle-id <id> | --display <n> [--rect x,y,w,h] [--no-shadow] [--duration 10 | -- <command> [args…]] | --mark <label> [<id>] | --stop [<id>] | --status\n    Records that open window or display through Shot, without its microphone or camera, for at most \(Int(AgentRequest.maximumDuration / 60)) minutes, saved to the capture folder. --rect records that part of the screen, so anything in front of it shows. Without --duration it prints an id and returns at once; --stop ends it. With -- and a command, it records while the command runs, passes its output through, stops when it exits, and exits with its code. --mark labels this moment of the recording, and its key frames show it. Opens Shot in the background if it isn't running; needs Settings › Agents › Let agents capture and record on.",
            "watch": "\(program) watch [--kind image|video|any] [--timeout 60] [--follow]\n    Waits for your next capture and prints its name, path, kind and when it was taken. Exits with 66 if none comes before the timeout. --follow prints one line per capture as each comes, until interrupted or the timeout. Reads the capture folder only, so Shot needn't be running.",
            "pick": "\(program) pick [--prompt <what to select>] [--timeout 60]\n    Asks you to select an area, window or display on Shot's capture overlay, showing the prompt and that the command line is asking, then saves the screenshot to the capture folder and prints its path, size and bytes. Esc cancels, which exits with 66, as does running out of time. Opens Shot in the background if it isn't running; works with Let agents capture and record off, since you make the selection.",
            "doctor": "\(program) doctor\n    Checks which copy of Shot answers and its version, Let agents capture and record, the socket, the Screen Recording permission and the capture folder, and says how to fix each problem. Exits 1 if a check fails.",
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
        64 a wrong option, 65 a file or marks Shot can't use, 66 no such file, capture, window or recording, no new
        capture, or a pick cancelled, 69 Shot isn't answering agents, 70 an internal error, 73 the output can't be made, 74 reading or writing
        failed, 75 Shot is busy, 77 no Screen Recording permission. More: \(docs)#the-shot-command-line
        """
    }

    /// The online docs, which render `docs/usage.md`.
    static let docs = "https://shot.lorcanchinnock.com/docs/"

    /// `value` on one line, as `shot watch --follow` prints each capture, so each line is a whole JSON object.
    public static func jsonLine(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

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

    /// The types a mark can have. `rounded` is an alias of `rectangle` that takes a default corner radius.
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
