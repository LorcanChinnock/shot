import Foundation

/// The MCP server's tools: four that read captures, and three that make new files from one, never changing, moving or
/// deleting anything. What they're called, what they take, and what they say back are here. Finding files, drawing
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
    public var now: @Sendable () -> Date
    public var timeZone: TimeZone

    public init(
        folder: URL,
        entries: @escaping @Sendable () -> [AgentCaptures.Entry],
        preview: @escaping @Sendable (AgentCaptures.Entry) async -> [MCPServer.Content],
        record: @escaping @Sendable (AgentCaptures.Entry) -> CaptureRecord? = { _ in nil },
        run: @escaping @Sendable (ShotCommand) async throws(ShotCommandError) -> JSONValue = { _ throws(ShotCommandError) in throw .internal("can't run commands here") },
        frames: @escaping @Sendable (AgentCaptures.Entry, Int) async throws(ShotCommandError) -> [MCPServer.Content] = { _, _ throws(ShotCommandError) in throw .internal("can't read frames here") },
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) {
        self.folder = folder
        self.entries = entries
        self.preview = preview
        self.record = record
        self.run = run
        self.frames = frames
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

    private static let capture: [String: JSONValue] = [
        "path": .object(["type": .string("string"), "description": .string("The capture's full path. Without path or name, the newest one.")]),
        "name": .object(["type": .string("string"), "description": .string("Its file name, or words from it.")]),
    ]
    private static func seconds(_ what: String) -> JSONValue {
        .object(["type": .string("number"), "description": .string(what)])
    }

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
            ])
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
            ])
        ),
        MCPServer.Tool(
            name: getCapture,
            description: "One Shot capture by path or by name, matched loosely (\"shot 14.03\" finds \"Shot 2026-10-10 at 14.03.12.png\"). Returns what latest_capture does.",
            inputSchema: schema([
                "path": .object(["type": .string("string"), "description": .string("The capture's full path.")]),
                "name": .object(["type": .string("string"), "description": .string("Its file name, or words from it.")]),
            ])
        ),
        MCPServer.Tool(
            name: getFrames,
            description: "Still frames of a Shot recording, since a model can't watch video: the first and last, and the frame after each change on screen once it settles, each with its time in seconds. Use this to see what happened in a recording, such as the steps of a bug. Reads only; writes nothing.",
            inputSchema: schema(capture.merging([
                "count": .object(["type": .string("integer"), "description": .string("How many frames, 1 to \(ShotCommand.FramesOptions.maximumCount). Default 8.")]),
            ]) { $1 })
        ),
        MCPServer.Tool(
            name: annotate,
            description: "Draws marks on a copy of a screenshot, to point the user at something: arrows, boxes, numbered counters, text and notes. The copy is saved beside the original as its next version, which the user can open in Shot and change; nothing is overwritten. Coordinates are in the full-size file's pixels, top-left origin. Returns the new file's path and a preview.",
            inputSchema: schema(capture.merging([
                "annotations": .object([
                    "type": .string("array"),
                    "description": .string("The marks, each with a type (arrow, line, rectangle, rounded, ellipse, highlight, blur, pixelate, text, note, counter, pen or marker) and its geometry: from and to as [x, y] for arrow and line; rect as [x, y, width, height] for shapes, text and notes; center as [x, y] for counter; points as [[x, y], …] for pen and marker. Optional: color (red, orange, yellow, green, blue, black or white), text for text and note, number for counter."),
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
        default:
            return MCPServer.ToolResult(content: [.text("Unknown tool: \(name)")], isError: true)
        }
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
            return MCPServer.ToolResult(content: [.text("No capture matches \"\(query)\": \(empty(entries, kind: .any))")], isError: true)
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
        return MCPServer.ToolResult(content: [.text("No capture matches \"\(query)\". The \(which) are \(names).")], isError: true)
    }

    func metadata(_ entry: AgentCaptures.Entry) -> JSONValue {
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
