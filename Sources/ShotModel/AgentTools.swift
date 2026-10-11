import Foundation

/// The MCP server's three read-only tools: what they're called, what they take, and what they say back. Finding files
/// and drawing previews need Apple frameworks, so they come in as closures; ShotCore's `live(folder:)` supplies them.
public struct AgentTools: Sendable {
    /// The folder the captures are read from, named when it has none.
    public var folder: URL
    /// Every capture in `folder`, in any order.
    public var entries: @Sendable () -> [AgentCaptures.Entry]
    /// What an agent sees of a capture: a downscaled image, or a video's poster frame and duration.
    public var preview: @Sendable (AgentCaptures.Entry) async -> [MCPServer.Content]
    public var now: @Sendable () -> Date
    public var timeZone: TimeZone

    public init(
        folder: URL,
        entries: @escaping @Sendable () -> [AgentCaptures.Entry],
        preview: @escaping @Sendable (AgentCaptures.Entry) async -> [MCPServer.Content],
        now: @escaping @Sendable () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) {
        self.folder = folder
        self.entries = entries
        self.preview = preview
        self.now = now
        self.timeZone = timeZone
    }

    public static let latestCapture = "latest_capture"
    public static let listCaptures = "list_captures"
    public static let getCapture = "get_capture"

    public static let definitions: [MCPServer.Tool] = [
        MCPServer.Tool(
            name: latestCapture,
            description: "The newest screenshot or recording taken with Shot: a preview image (a poster frame for a video), its full-size path, and, when there is one, its .shot.json listing what the user marked on it (arrows, boxes, text, numbered counters) in the full-size file's pixels. Use this when the user mentions their latest screenshot or what they marked.",
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
            description: "Recent Shot captures, newest first: name, path, kind, when it was taken and whether a .shot.json describes its markup. No images; pass a name to get_capture to see one.",
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
        default:
            return MCPServer.ToolResult(content: [.text("Unknown tool: \(name)")], isError: true)
        }
    }

    /// The preview, then the capture's details, then its `.shot.json` read as it is on disk.
    func describe(_ entry: AgentCaptures.Entry) async -> MCPServer.ToolResult {
        var content = await preview(entry)
        content.append(.text(Self.json(metadata(entry))))
        if let sidecar = sidecarText(for: entry) {
            content.append(.text(sidecar))
        } else if !entry.isVideo {
            content.append(.text("No .shot.json beside it, so Shot has no record of its markup. Turning on Settings › Agents › Hand captures to agents writes one for each new capture."))
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
        var object: [String: JSONValue] = [
            "name": .string(entry.name),
            "path": .string(entry.url.path),
            "kind": .string(entry.isVideo ? "video" : "image"),
            "created": .string(stamp(entry.date)),
        ]
        let sidecar = CaptureSidecar.url(for: entry.url)
        if FileManager.default.fileExists(atPath: sidecar.path) {
            object["shotJSON"] = .string(sidecar.path)
        }
        return .object(object)
    }

    /// The `.shot.json` as written, so the agent reads the documented schema rather than a summary of it.
    func sidecarText(for entry: AgentCaptures.Entry) -> String? {
        (try? Data(contentsOf: CaptureSidecar.url(for: entry.url))).flatMap { String(data: $0, encoding: .utf8) }
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

    private static func schema(_ properties: [String: JSONValue]) -> JSONValue {
        .object(["type": .string("object"), "properties": .object(properties)])
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }
}
