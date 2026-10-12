import Foundation

/// The MCP server's tools: six that read captures, one by waiting for the next, four that make new files from them, never changing, moving or
/// deleting anything, and three that ask the running app to list, capture or record windows. What they're called, what they
/// take, and what they say back are here. Finding files, drawing
/// previews and running the commands need Apple frameworks, so they come in as closures; ShotCore's `live(folder:)`
/// supplies them.
public struct AgentTools: Sendable {
    /// The folder the captures are read from, named when it has none.
    public var folder: URL
    /// Every capture in `folder`, in any order.
    public var entries: @Sendable () -> [AgentCaptures.Entry]
    /// What an agent sees of a capture: a downscaled image, or a video's poster frame and duration.
    public var preview: @Sendable (AgentCaptures.Entry) async -> [MCPServer.Content]
    /// The record Shot wrote inside a capture, read from the file's metadata.
    public var record: @Sendable (AgentCaptures.Entry) -> CaptureRecord?
    /// Runs a `shot` command, as the command line does, for the tools that make files.
    public var run: @Sendable (ShotCommand) async throws(ShotCommandError) -> JSONValue
    /// Up to the given number of a recording's key frames, each as its time then its image.
    public var frames: @Sendable (AgentCaptures.Entry, Int) async throws(ShotCommandError) -> [MCPServer.Content]
    /// The text in a screenshot, read on the device.
    public var text: @Sendable (AgentCaptures.Entry) async throws(ShotCommandError) -> CaptureText
    /// Sends a request to the running app over its agent socket, and gives back its answer's fields.
    public var agent: @Sendable (AgentRequest) async throws(ShotCommandError) -> [String: JSONValue]
    public var now: @Sendable () -> Date
    public var timeZone: TimeZone
    /// How often `wait_for_capture` looks at the folder.
    public var pollInterval: Duration = CaptureWatch.interval

    public init(
        folder: URL,
        entries: @escaping @Sendable () -> [AgentCaptures.Entry],
        preview: @escaping @Sendable (AgentCaptures.Entry) async -> [MCPServer.Content],
        record: @escaping @Sendable (AgentCaptures.Entry) -> CaptureRecord? = { _ in nil },
        run: @escaping @Sendable (ShotCommand) async throws(ShotCommandError) -> JSONValue = { _ throws(ShotCommandError) in throw .internal("can't run commands here") },
        frames: @escaping @Sendable (AgentCaptures.Entry, Int) async throws(ShotCommandError) -> [MCPServer.Content] = { _, _ throws(ShotCommandError) in throw .internal("can't read frames here") },
        text: @escaping @Sendable (AgentCaptures.Entry) async throws(ShotCommandError) -> CaptureText = { _ throws(ShotCommandError) in throw .internal("can't read text here") },
        agent: @escaping @Sendable (AgentRequest) async throws(ShotCommandError) -> [String: JSONValue] = { _ throws(ShotCommandError) in throw .unavailable("can't reach Shot from here") },
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) {
        self.folder = folder
        self.entries = entries
        self.preview = preview
        self.record = record
        self.run = run
        self.frames = frames
        self.text = text
        self.agent = agent
        self.now = now
        self.timeZone = timeZone
    }

    public static let latestCapture = "latest_capture"
    public static let listCaptures = "list_captures"
    public static let getCapture = "get_capture"
    public static let annotate = "annotate"
    public static let makeGIF = "make_gif"
    public static let trimVideo = "trim_video"
    public static let getFrames = "get_frames"
    public static let findText = "find_text"
    public static let waitForCapture = "wait_for_capture"
    public static let captureWindow = "capture_window"
    public static let recordWindow = "record_window"
    public static let compare = "compare"
    public static let listWindows = "list_windows"
    /// The longest `record_window` and `wait_for_capture` wait for, so their answer comes within what clients wait for a tool.
    public static let maximumWait: Double = 120
    /// How long `wait_for_capture` waits without a timeout.
    public static let defaultWait: Double = 60
    /// How many key frames a finished `record_window` shows.
    static let recordingFrames = 6

    private static let capture: [String: JSONValue] = [
        "path": .object(["type": .string("string"), "description": .string("The capture's full path. Only captures in Shot's capture folder can be named. Without path or name, the newest one.")]),
        "name": .object(["type": .string("string"), "description": .string("Its file name, or words from it.")]),
    ]
    /// The types `annotate` can draw, for its description: every type but a placed image, whose pixels a mark can't hold.
    private static let markTypes: String = {
        let types = CaptureMark.types.subtracting(["image"]).sorted()
        return types.dropLast().joined(separator: ", ") + " or " + (types.last ?? "")
    }()
    /// The palette names `annotate` takes as `color`, for its description.
    private static let colorNames = CaptureMark.paletteNames.dropLast().joined(separator: ", ") + " or " + (CaptureMark.paletteNames.last ?? "")
    private static func seconds(_ what: String) -> JSONValue {
        .object(["type": .string("number"), "description": .string(what)])
    }
    /// What `capture_window` and `record_window` can point at besides words from the window.
    private static let target: [String: JSONValue] = [
        "bundleID": .object(["type": .string("string"), "description": .string("The app's bundle ID, such as \"com.apple.iphonesimulator\", for its front window, or with window, the one of its windows that names. list_windows gives them.")]),
        "display": .object(["type": .string("integer"), "description": .string("A whole display instead of a window, numbered from 1 as list_windows gives them.")]),
        "rect": .object([
            "type": .string("array"),
            "items": .object(["type": .string("number")]),
            "description": .string("Only this part, as [x, y, width, height] in points from the window's or display's top-left corner. list_windows gives each window's size in points."),
        ]),
        "noShadow": .object(["type": .string("boolean"), "description": .string("Leaves out the window's shadow, whatever the user's setting.")]),
    ]

    public static let definitions: [MCPServer.Tool] = [
        MCPServer.Tool(
            name: latestCapture,
            description: "The screenshot or recording the user just took with Shot: a preview image (a poster frame for a video), its full-size path, and, when Shot recorded it, which app and window it came from, the user's notes, and what they marked (arrows, boxes, text, numbered counters) in the full-size file's pixels. Use this when the user mentions the screenshot they just took, their latest screenshot, or what they marked.",
            inputSchema: schema([
                "kind": .object([
                    "type": .string("string"),
                    "enum": .array([.string("image"), .string("video"), .string("any")]),
                    "description": .string("image (the default), video or any."),
                ]),
            ]),
            readOnly: true
        ),
        MCPServer.Tool(
            name: listCaptures,
            description: "Recent Shot captures, newest first: name, path, kind and when it was taken. No images; pass a name to get_capture to see one.",
            inputSchema: schema([
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("How many, 1 to \(AgentCaptures.maximumLimit). Default \(AgentCaptures.defaultLimit)."),
                ]),
                "since": .object([
                    "type": .string("string"),
                    "description": .string("Only captures from then on: an ISO 8601 date or date and time, or a span back from now such as 10m, 2h or 3d."),
                ]),
            ]),
            readOnly: true
        ),
        MCPServer.Tool(
            name: getCapture,
            description: "One Shot capture by path or by name, matched loosely (\"shot 14.03\" finds \"Shot 2026-10-10 at 14.03.12.png\"). With neither, the newest capture, screenshot or recording. Returns what latest_capture does.",
            inputSchema: schema([
                "path": .object(["type": .string("string"), "description": .string("The capture's full path. Only captures in Shot's capture folder can be named.")]),
                "name": .object(["type": .string("string"), "description": .string("Its file name, or words from it.")]),
            ]),
            readOnly: true
        ),
        MCPServer.Tool(
            name: getFrames,
            description: "Still frames of a Shot recording, since a model can't watch video: the first and last, and the frame after each change on screen once it settles, each with its time in seconds. Use this to see what happened in a recording, such as the steps of a bug. Reads only; writes nothing.",
            inputSchema: schema(capture.merging([
                "count": .object(["type": .string("integer"), "description": .string("How many frames, 1 to \(ShotCommand.FramesOptions.maximumCount). Default 8.")]),
            ]) { $1 }),
            readOnly: true
        ),
        MCPServer.Tool(
            name: findText,
            description: "Reads the text in a Shot screenshot, on this Mac: each line with its box as [x, y, width, height] in the full-size file's pixels, top-left origin, the space annotate takes. With query, only the lines that contain it, each with the box of the words that match, to check what the screen says or find where something is, such as a button to point at. Without path or name, the newest screenshot. Reads only; writes nothing.",
            inputSchema: schema(capture.merging([
                "query": .object(["type": .string("string"), "description": .string("Words to find, ignoring case and accents, such as \"Save\". Without it, all the text.")]),
            ]) { $1 }),
            readOnly: true
        ),
        MCPServer.Tool(
            name: waitForCapture,
            description: "Waits for the user's next Shot capture and returns it as latest_capture does. Use this when you've asked the user to take a screenshot or recording, so you can carry on once they have. Only a capture taken after the call counts. Reads the capture folder only; writes nothing.",
            inputSchema: schema([
                "kind": .object([
                    "type": .string("string"),
                    "enum": .array([.string("image"), .string("video"), .string("any")]),
                    "description": .string("image, video or any (the default)."),
                ]),
                "timeout": seconds("How long to wait, up to \(Int(maximumWait)) seconds. Default \(Int(defaultWait))."),
            ]),
            readOnly: true
        ),
        MCPServer.Tool(
            name: annotate,
            description: "Draws marks on a copy of a screenshot, to point the user at something: arrows, boxes, numbered counters, text and notes. The copy is saved beside the original as its next version, which the user can open in Shot and change; nothing is overwritten. Coordinates are in the full-size file's pixels, top-left origin. Returns the new file's path and a preview.",
            inputSchema: schema(capture.merging([
                "annotations": .object([
                    "type": .string("array"),
                    "description": .string("The marks, each with a type (\(markTypes)) and its geometry: from and to as [x, y] for arrow and line; center as [x, y] for counter; points as [[x, y], …] for pen and marker; rect as [x, y, width, height] for every other type. Optional: color (\(colorNames)), or hex (#RRGGBB) for any other colour; text for text and note; number for counter."),
                    "items": .object(["type": .string("object")]),
                ]),
            ]) { $1 }, required: ["annotations"])
        ),
        MCPServer.Tool(
            name: makeGIF,
            description: "Makes a GIF of a Shot recording, or part of it, for a pull request or README. Saved beside the recording; nothing is overwritten. GIFs stop at 60 seconds. Returns the GIF's path, size and frame count.",
            inputSchema: schema(capture.merging([
                "start": seconds("Where to start, in seconds. Default 0."),
                "end": seconds("Where to end, in seconds. Default the end."),
                "fps": .object(["type": .string("number"), "description": .string("Frames per second, 1 to 30. Default 12.")]),
                "width": .object(["type": .string("integer"), "description": .string("Width in pixels, 16 to 8192, or 0 for the recording's own. Default 720.")]),
            ]) { $1 })
        ),
        MCPServer.Tool(
            name: trimVideo,
            description: "Saves the part of a Shot recording between two times as a new video beside it, without re-encoding where it can. Nothing is overwritten. Returns the new video's path and length.",
            inputSchema: schema(capture.merging([
                "start": seconds("Where to start, in seconds."),
                "end": seconds("Where to end, in seconds."),
            ]) { $1 }, required: ["start", "end"])
        ),
        MCPServer.Tool(
            name: listWindows,
            description: "The open windows, front to back, through the running Shot app: each one's app, bundle ID, title, size in points and whether it's the frontmost, and the displays. Use it to pick what capture_window or record_window should point at. Shot opens in the background if it isn't running. Needs Settings › Agents › Let agents capture and record turned on.",
            inputSchema: schema([:]),
            readOnly: true
        ),
        MCPServer.Tool(
            name: captureWindow,
            description: "Takes a screenshot of an open window, such as the iOS Simulator or the app you're building, or of a whole display, through the running Shot app, without bringing it forward or taking focus, even when other windows cover it. Saved to the capture folder; returns a preview, its path and which window it was. Shot opens in the background if it isn't running. Needs Settings › Agents › Let agents capture and record turned on, and Shot shows a notice each time. If no window matches, the error lists the open ones.",
            inputSchema: schema(target.merging([
                "window": .object(["type": .string("string"), "description": .string("Words from the window's title or its app's name, such as \"Simulator\" or \"Calculator\". Case and accents don't matter.")]),
                "waitStable": .object([
                    "type": .string("number"),
                    "description": .string("Waits up to this many seconds, at most \(Int(AgentTarget.maximumWaitStable)), for the picture to stop changing first, such as after a tap starts an animation. If it never settles, the screenshot is taken anyway. \(Int(AgentTarget.defaultWaitStable)) suits most animations."),
                ]),
            ]) { $1 })
        ),
        MCPServer.Tool(
            name: recordWindow,
            description: "Records an open window through the running Shot app, such as the Simulator while a UI test runs, then shows what happened. Saved to the capture folder. With a duration of up to \(Int(maximumWait)) seconds it waits, then returns the recording's path and about \(recordingFrames) key frames, each with its time. Without one it starts and returns an id; call again with action stop to end it and get the frames. Never records the microphone or camera, stops itself after \(Int(AgentRequest.maximumDuration / 60)) minutes, and Shot shows a red border, its stop controls and a notice, so the user can stop it. Shot opens in the background if it isn't running. Needs Settings › Agents › Let agents capture and record turned on.",
            inputSchema: schema(target.merging([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([.string("start"), .string("stop")]),
                    "description": .string("start (the default) or stop."),
                ]),
                "window": .object(["type": .string("string"), "description": .string("For start: words from the window's title or its app's name, such as \"Simulator\".")]),
                "duration": seconds("For start: how long to record, up to \(Int(maximumWait)) seconds, waiting for it to end. Without it, the recording runs until stopped."),
                "id": .object(["type": .string("string"), "description": .string("For stop: the id start gave. Without it, stops the agent's recording in progress.")]),
            ]) { $1 })
        ),
        MCPServer.Tool(
            name: compare,
            description: "Compares two Shot screenshots, such as before and after a fix, to check what moved or changed and that nothing else did. Returns a diff image (a dimmed copy of b with the changes highlighted and boxed), the boxes of the changed regions as [x, y, width, height] in b's pixels, and the share of pixels changed. Screenshots of different sizes are compared at b's size, and the result says so. The diff is saved beside b as a new file; neither screenshot changes.",
            inputSchema: schema([
                "a": .object(["type": .string("string"), "description": .string("The screenshot before: its full path in Shot's capture folder, or its file name or words from it.")]),
                "b": .object(["type": .string("string"), "description": .string("The screenshot after, named the same way. The regions are in its pixels.")]),
                "threshold": .object(["type": .string("number"), "description": .string("How much a colour may change, from 0 to 1 of its range, and still count as the same, so anti-aliasing isn't reported. 0 counts any difference. Default \(ImageDiff.defaultThreshold).")]),
            ], required: ["a", "b"])
        ),
    ]

    public func server(version: String) -> MCPServer {
        MCPServer(name: "shot", version: version, tools: Self.definitions) { name, arguments in
            await call(name, arguments)
        }
    }

    /// Runs the tool `name`, which `MCPServer` has already matched to one of `definitions`.
    public func call(_ name: String, _ arguments: JSONValue) async -> MCPServer.ToolResult {
        let entries = entries()
        switch name {
        case Self.latestCapture:
            // The issue's default is the newest image, since that's what "my latest screenshot" means.
            let kind = arguments["kind"]?.string == nil ? AgentCaptures.Kind.image : AgentCaptures.Kind(lenient: arguments["kind"]?.string)
            guard let entry = AgentCaptures.latest(entries, kind: kind) else {
                return MCPServer.ToolResult(content: [.text(empty(entries, kind: kind))])
            }
            return await describe(entry)
        case Self.listCaptures:
            return list(entries, arguments)
        case Self.getCapture:
            let query = (arguments["path"]?.string ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? arguments["name"]?.string : arguments["path"]?.string
            guard let query, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                guard let entry = AgentCaptures.latest(entries, kind: .any) else {
                    return MCPServer.ToolResult(content: [.text(empty(entries, kind: .any))])
                }
                return await describe(entry)
            }
            guard let entry = AgentCaptures.named(query, in: entries) else {
                return notFound(query, in: entries)
            }
            return await describe(entry)
        case Self.waitForCapture:
            return await waitForCapture(arguments)
        case Self.annotate, Self.makeGIF, Self.trimVideo:
            return await make(name, arguments, entries)
        case Self.getFrames:
            let query = [arguments["path"]?.string, arguments["name"]?.string].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let entry = query.map({ AgentCaptures.named($0, in: entries) }) ?? AgentCaptures.latest(entries, kind: .video) else {
                return query.map { notFound($0, in: entries) } ?? MCPServer.ToolResult(content: [.text(empty(entries, kind: .video))], isError: true)
            }
            guard entry.isVideo else {
                return MCPServer.ToolResult(content: [.text("\(entry.name) is a screenshot; get_frames needs a recording. latest_capture or get_capture shows a screenshot.")], isError: true)
            }
            let count = arguments["count"]?.number.flatMap { $0.isFinite ? Int(min(max($0, 1), Double(ShotCommand.FramesOptions.maximumCount))) : nil } ?? 8
            do {
                return MCPServer.ToolResult(content: [.text("\(entry.name), at \(entry.url.path):")] + (try await frames(entry, count)))
            } catch {
                return MCPServer.ToolResult(content: [.text(error.message)], isError: true)
            }
        case Self.findText:
            return await findText(arguments, entries)
        case Self.captureWindow:
            return await captureWindow(arguments)
        case Self.recordWindow:
            return await recordWindow(arguments)
        case Self.compare:
            return await compare(arguments, entries)
        case Self.listWindows:
            do {
                return MCPServer.ToolResult(content: [.text(Self.json(.object(try await agent(AgentRequest(.windows)))))])
            } catch {
                return MCPServer.ToolResult(content: [.text(error.message)], isError: true)
            }
        default:
            return MCPServer.ToolResult(content: [.text("Unknown tool: \(name)")], isError: true)
        }
    }

    /// Waits for the next capture of the kind `arguments` asks for, then shows it as `latest_capture` does. Running out
    /// of time isn't an error, since the user may just not have taken it yet.
    func waitForCapture(_ arguments: JSONValue) async -> MCPServer.ToolResult {
        let kind = AgentCaptures.Kind(lenient: arguments["kind"]?.string)
        let timeout = arguments["timeout"]?.number.flatMap { $0.isFinite ? min(max($0, 1), Self.maximumWait) : nil } ?? Self.defaultWait
        guard let entry = await CaptureWatch.next(kind: kind, timeout: timeout, interval: pollInterval, entries: entries) else {
            let noun = switch kind {
            case .image: "screenshot"
            case .video: "recording"
            case .any: "capture"
            }
            return MCPServer.ToolResult(content: [.text("No new \(noun) in \(folder.path) after \(String(format: "%g", timeout)) second\(timeout == 1 ? "" : "s"). Call wait_for_capture again to keep waiting.")])
        }
        return await describe(entry)
    }

    /// Runs one of the tools that make a file, on the capture `arguments` name, or the newest one of the right kind.
    /// Only captures in the folder can be named, so nothing outside it is read or written beside.
    func make(_ name: String, _ arguments: JSONValue, _ entries: [AgentCaptures.Entry]) async -> MCPServer.ToolResult {
        let video = name != Self.annotate
        let query = [arguments["path"]?.string, arguments["name"]?.string].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let found = query.map { AgentCaptures.named($0, in: entries) } ?? AgentCaptures.latest(entries, kind: video ? .video : .image)
        guard let entry = found else {
            return query.map { notFound($0, in: entries) } ?? MCPServer.ToolResult(content: [.text(empty(entries, kind: video ? .video : .image))], isError: true)
        }
        guard entry.isVideo == video else {
            return MCPServer.ToolResult(content: [.text("\(entry.name) is \(entry.isVideo ? "a recording" : "a screenshot"); \(name) needs \(video ? "a recording" : "a screenshot").")], isError: true)
        }
        let command: ShotCommand
        switch name {
        case Self.annotate:
            guard let marks = arguments["annotations"], case .array = marks, let data = try? JSONEncoder().encode(marks) else {
                return MCPServer.ToolResult(content: [.text("annotate needs annotations: an array of marks.")], isError: true)
            }
            do {
                command = .annotate(ShotCommand.AnnotateOptions(input: entry.url.path, marks: .marks(try CaptureMark.list(from: data))))
            } catch {
                return MCPServer.ToolResult(content: [.text(error.message)], isError: true)
            }
        case Self.makeGIF:
            var options = ShotCommand.GIFOptions(input: entry.url.path, start: arguments["start"]?.number, end: arguments["end"]?.number)
            // Lenient like the other tools: out-of-range values are brought into range rather than refused.
            if let fps = arguments["fps"]?.number, fps.isFinite {
                options.fps = min(max(fps, 1), 30)
            }
            if let width = arguments["width"]?.number, width.isFinite {
                options.width = width <= 0 ? 0 : Int(min(max(width, 16), 8192))
            }
            command = .gif(options)
        default:
            guard let start = arguments["start"]?.number, let end = arguments["end"]?.number, start.isFinite, end.isFinite, end > start, start >= 0 else {
                return MCPServer.ToolResult(content: [.text("trim_video needs start and end in seconds, with end after start.")], isError: true)
            }
            command = .trim(ShotCommand.TrimOptions(input: entry.url.path, start: start, end: end))
        }
        let result: JSONValue
        do {
            result = try await run(command)
        } catch {
            return MCPServer.ToolResult(content: [.text(error.message)], isError: true)
        }
        var content: [MCPServer.Content] = [.text(Self.json(result))]
        if name == Self.annotate, let path = result["path"]?.string {
            content = await preview(AgentCaptures.Entry(url: URL(fileURLWithPath: path), isVideo: false, date: now())) + content
        }
        content.append(.text("Saved as a new file beside \(entry.name); the original is unchanged."))
        return MCPServer.ToolResult(content: content)
    }

    /// The text in the screenshot `arguments` names, or the newest one: every line, or with a query only the lines that
    /// contain it, each with its box. Words are left out, since an agent rarely needs them and they'd fill its context.
    func findText(_ arguments: JSONValue, _ entries: [AgentCaptures.Entry]) async -> MCPServer.ToolResult {
        let name = [arguments["path"]?.string, arguments["name"]?.string].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let entry = name.map({ AgentCaptures.named($0, in: entries) }) ?? AgentCaptures.latest(entries, kind: .image) else {
            return name.map { notFound($0, in: entries) } ?? MCPServer.ToolResult(content: [.text(empty(entries, kind: .image))], isError: true)
        }
        guard !entry.isVideo else {
            return MCPServer.ToolResult(content: [.text("\(entry.name) is a recording; find_text reads screenshots. get_frames shows a recording's frames.")], isError: true)
        }
        let read: CaptureText
        do {
            read = try await text(entry)
        } catch {
            return MCPServer.ToolResult(content: [.text(error.message)], isError: true)
        }
        var object = read.json(words: false)
        object["name"] = .string(entry.name)
        object["path"] = .string(entry.url.path)
        guard let query = arguments["query"]?.string, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let note = read.lines.isEmpty ? "No text found in \(entry.name)." : "Boxes are [x, y, width, height] in the file's pixels, from the top left."
            return MCPServer.ToolResult(content: [.text(Self.json(.object(object))), .text(note)])
        }
        let hits = read.lines(matching: query)
        object["lines"] = nil
        object["query"] = .string(query)
        object["matches"] = .array(hits.map { hit in
            .object(["text": .string(hit.line.text), "box": CaptureText.json(hit.line.box), "match": CaptureText.json(hit.box)])
        })
        // The whole text stays only when nothing matched, so the agent sees what the screen says instead.
        if !hits.isEmpty {
            object["text"] = nil
        }
        let note = if read.lines.isEmpty {
            "No text found in \(entry.name)."
        } else if hits.isEmpty {
            "No line in \(entry.name) contains \"\(query)\"; text is everything it reads."
        } else {
            "match is the box of the words that matched, inside the line's box. Both are [x, y, width, height] in the file's pixels, from the top left."
        }
        return MCPServer.ToolResult(content: [.text(Self.json(.object(object))), .text(note)])
    }

    /// Compares the screenshots `a` and `b` name, which must both be in the folder, and shows the diff it saved beside `b`.
    func compare(_ arguments: JSONValue, _ entries: [AgentCaptures.Entry]) async -> MCPServer.ToolResult {
        var found: [AgentCaptures.Entry] = []
        for key in ["a", "b"] {
            guard let query = arguments[key]?.string, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                return MCPServer.ToolResult(content: [.text("compare needs a and b: the screenshots before and after, each a path or words from its name.")], isError: true)
            }
            guard let entry = AgentCaptures.named(query, in: entries) else {
                return notFound(query, in: entries)
            }
            guard !entry.isVideo else {
                return MCPServer.ToolResult(content: [.text("\(entry.name) is a recording; compare needs two screenshots. get_frames shows a recording's frames.")], isError: true)
            }
            found.append(entry)
        }
        var options = ShotCommand.DiffOptions(a: found[0].url.path, b: found[1].url.path)
        // Lenient like the other tools: a threshold out of range is brought into it.
        if let threshold = arguments["threshold"]?.number, threshold.isFinite {
            options.threshold = min(max(threshold, 0), 1)
        }
        let result: JSONValue
        do {
            result = try await run(.diff(options))
        } catch {
            return MCPServer.ToolResult(content: [.text(error.message)], isError: true)
        }
        var content: [MCPServer.Content] = []
        if let path = result["path"]?.string {
            content = await preview(AgentCaptures.Entry(url: URL(fileURLWithPath: path), isVideo: false, date: now()))
        }
        content.append(.text(Self.json(result)))
        content.append(.text("Saved the diff as a new file beside \(found[1].name); neither screenshot is changed."))
        return MCPServer.ToolResult(content: content)
    }

    /// What `capture_window` or `record_window` is pointed at, from `arguments`. Lenient like the other tools: a
    /// `waitStable` past the most is brought down to it.
    static func target(_ arguments: JSONValue) -> AgentTarget {
        func text(_ key: String) -> String? {
            arguments[key]?.string.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        var target = AgentTarget(window: text("window"), bundleID: text("bundleID"), noShadow: arguments["noShadow"] == .bool(true))
        if let display = arguments["display"]?.number {
            target.display = display.isFinite ? Int(exactly: display) ?? 0 : 0
        }
        if let rect = arguments["rect"] {
            if case let .array(items) = rect {
                target.rect = items.map { $0.number ?? .nan }
            } else {
                target.rect = []
            }
        }
        switch arguments["waitStable"] {
        case .bool(true)?:
            target.waitStable = AgentTarget.defaultWaitStable
        case let value? where value.number?.isFinite == true:
            target.waitStable = min(value.number ?? 0, AgentTarget.maximumWaitStable)
        default:
            break
        }
        return target
    }

    /// Asks the app for a screenshot of the window `arguments` names, then shows it as `describe` does a capture.
    func captureWindow(_ arguments: JSONValue) async -> MCPServer.ToolResult {
        let target = Self.target(arguments)
        if let problem = target.problem {
            return MCPServer.ToolResult(content: [.text("capture_window \(problem).")], isError: true)
        }
        let fields: [String: JSONValue]
        do {
            fields = try await agent(AgentRequest(.capture, target: target))
        } catch {
            return MCPServer.ToolResult(content: [.text(error.message)], isError: true)
        }
        guard let path = fields["path"]?.string else {
            return MCPServer.ToolResult(content: [.text("Shot took the screenshot but didn't say where it saved it.")], isError: true)
        }
        let entry = AgentCaptures.Entry(url: URL(fileURLWithPath: path), isVideo: false, date: now())
        var content = await preview(entry)
        content.append(.text(Self.json(.object(fields))))
        let lines = record(entry)?.summaryLines ?? []
        if !lines.isEmpty {
            content.append(.text(lines.joined(separator: "\n")))
        }
        return MCPServer.ToolResult(content: content)
    }

    /// Starts or stops a recording through the app. A finished one comes back with its key frames, since that's what
    /// an agent can see of it.
    func recordWindow(_ arguments: JSONValue) async -> MCPServer.ToolResult {
        let action = arguments["action"]?.string?.trimmingCharacters(in: .whitespaces).lowercased() ?? "start"
        let request: AgentRequest
        var notes: [String] = []
        switch action {
        case "stop":
            let id = arguments["id"]?.string.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            request = AgentRequest(.stop, id: id)
        case "start", "":
            var target = Self.target(arguments)
            // Only a screenshot waits for the picture to settle; a recording shows it settling anyway.
            target.waitStable = nil
            if let problem = target.problem {
                return MCPServer.ToolResult(content: [.text("record_window \(problem).")], isError: true)
            }
            var duration = arguments["duration"]?.number.flatMap { $0.isFinite ? $0 : nil }
            if let asked = duration, asked > Self.maximumWait {
                notes.append("Recorded \(Int(Self.maximumWait)) seconds, the most record_window waits for; for longer, start without a duration and stop it.")
                duration = Self.maximumWait
            } else if let asked = duration, asked < 1 {
                duration = 1
            }
            request = AgentRequest(.record, target: target, duration: duration)
        default:
            return MCPServer.ToolResult(content: [.text("record_window's action is start or stop, not \"\(action)\".")], isError: true)
        }
        let fields: [String: JSONValue]
        do {
            fields = try await agent(request)
        } catch {
            return MCPServer.ToolResult(content: [.text(error.message)], isError: true)
        }
        var content: [MCPServer.Content] = [.text(Self.json(.object(fields)))] + notes.map(MCPServer.Content.text)
        guard let path = fields["path"]?.string else {
            content.append(.text("Recording. Call record_window with action stop and id \(fields["id"]?.string ?? "") to end it; it stops itself after \(Int(AgentRequest.maximumDuration / 60)) minutes."))
            return MCPServer.ToolResult(content: content)
        }
        let entry = AgentCaptures.Entry(url: URL(fileURLWithPath: path), isVideo: true, date: now())
        do {
            content += try await frames(entry, Self.recordingFrames)
        } catch {
            content.append(.text("Saved, but its frames couldn't be read: \(error.message)"))
        }
        return MCPServer.ToolResult(content: content)
    }

    /// The preview, then the capture's details, then what Shot recorded in it, as plain lines.
    func describe(_ entry: AgentCaptures.Entry) async -> MCPServer.ToolResult {
        var content = await preview(entry)
        content.append(.text(Self.json(metadata(entry))))
        let lines = record(entry)?.summaryLines ?? []
        if !lines.isEmpty {
            content.append(.text(lines.joined(separator: "\n")))
        } else if !entry.isVideo {
            content.append(.text("Shot recorded nothing about where this came from or what was marked; the image shows any marks. Turning on Settings › Agents › Hand captures to agents records it in each new capture."))
        }
        return MCPServer.ToolResult(content: content)
    }

    func list(_ entries: [AgentCaptures.Entry], _ arguments: JSONValue) -> MCPServer.ToolResult {
        // Finite and in range before `Int`, which traps otherwise; a quoted "inf" reads as a number.
        let limit = arguments["limit"]?.number.flatMap { $0.isFinite ? Int(min(max($0, -1e6), 1e6).rounded()) : nil }
        var notes: [String] = []
        var since: Date?
        if let text = arguments["since"]?.string, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            since = AgentCaptures.date(since: text, now: now(), timeZone: timeZone)
            if since == nil {
                notes.append("Couldn't read since \"\(text)\", so these are from any time.")
            }
        }
        let listed = AgentCaptures.list(entries, limit: limit, since: since)
        guard !listed.isEmpty else {
            let text = entries.isEmpty ? empty(entries, kind: .any) : "No captures in \(folder.path) since \(stamp(since ?? now()))."
            return MCPServer.ToolResult(content: [.text((notes + [text]).joined(separator: "\n"))])
        }
        return MCPServer.ToolResult(content: [.text((notes + [Self.json(.array(listed.map(metadata)))]).joined(separator: "\n"))])
    }

    /// Not an error: an empty folder is a normal state, and saying where it looked lets the agent spot a wrong folder.
    func empty(_ entries: [AgentCaptures.Entry], kind: AgentCaptures.Kind) -> String {
        let noun = switch kind {
        case .image: "screenshots"
        case .video: "recordings"
        case .any: "captures"
        }
        return "No \(noun) in \(folder.path) yet."
    }

    /// An error naming the captures whose names share the most words with `query`, so the agent can try again.
    func notFound(_ query: String, in entries: [AgentCaptures.Entry]) -> MCPServer.ToolResult {
        let ranked = AgentCaptures.ranked(entries)
        guard !ranked.isEmpty else {
            return MCPServer.ToolResult(content: [.text("No capture matches \"\(query)\": \(empty(entries, kind: .any))\(outside(query))")], isError: true)
        }
        let wanted = Self.words(in: query)
        func shared(_ entry: AgentCaptures.Entry) -> Int {
            Self.words(in: entry.name).filter { word in wanted.contains { word.hasPrefix($0) } }.count
        }
        let scored: [(name: String, rank: Int, shared: Int)] = ranked.enumerated().map { ($1.name, $0, shared($1)) }
        let nearest = scored
            .sorted { $0.shared != $1.shared ? $0.shared > $1.shared : $0.rank < $1.rank }
            .prefix(5)
        let names = nearest.map { "\"\($0.name)\"" }.joined(separator: ", ")
        let which = nearest.contains { $0.shared > 0 } ? "nearest" : "newest"
        return MCPServer.ToolResult(content: [.text("No capture matches \"\(query)\".\(outside(query)) The \(which) are \(names).")], isError: true)
    }

    /// Why a full path outside `folder` names nothing, after a space, or nothing for a name or a path inside it.
    func outside(_ query: String) -> String {
        let path = (query.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let inside = folder.standardizedFileURL.path.hasSuffix("/") ? folder.standardizedFileURL.path : folder.standardizedFileURL.path + "/"
        guard path.hasPrefix("/"), !URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(inside) else {
            return ""
        }
        return " Only captures in Shot's capture folder, \(folder.path), can be named, and that path is outside it."
    }

    /// A capture's name, path, kind and when it was taken, as `list_captures` and `shot watch` give it.
    public func metadata(_ entry: AgentCaptures.Entry) -> JSONValue {
        let object: [String: JSONValue] = [
            "name": .string(entry.name),
            "path": .string(entry.url.path),
            "kind": .string(entry.isVideo ? "video" : "image"),
            "created": .string(stamp(entry.date)),
        ]
        return .object(object)
    }

    func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func json(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private static func schema(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var object: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty {
            object["required"] = .array(required.map(JSONValue.string))
        }
        return .object(object)
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }
}
