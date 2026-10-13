import Foundation

/// What the `shot` command line and the MCP server ask the running app over its agent socket: one JSON line per
/// connection, answered by one `AgentResponse` line. Here, with no socket, so every message is tested on Linux.
public struct AgentRequest: Codable, Equatable, Sendable {
    /// The protocol's version; a request with another is refused, so an old app never half-understands a new one.
    public static let version = 1
    /// The longest an agent's recording runs before it stops itself, in seconds.
    public static let maximumDuration: Double = 600

    public enum Operation: String, Codable, Sendable {
        /// A screenshot of the target.
        case capture
        /// A recording of the target: answered at once with its `id`, or with `duration`, when it ends.
        case record
        /// Ends the agent's recording `id`, or the agent's recording in progress.
        case stop
        /// Whether the app is capturing or recording.
        case status
        /// The open windows and the displays, for an agent to pick from.
        case windows
        /// Stamps `label` on the agent's recording `id`, or the agent's recording in progress, at the time it's at.
        case mark
    }

    public var v: Int
    public var op: Operation
    /// Words from the window's title or app, as `WindowMatch` reads them.
    public var window: String?
    /// How long to record, in seconds, above 0 and at most `maximumDuration`.
    public var duration: Double?
    /// A recording's ID, as `record` gave it.
    public var id: String?
    /// The rest of `AgentTarget`, sent only when set, so a plain request reads as it always has.
    public var bundleID: String?
    public var display: Int?
    public var rect: [Double]?
    public var noShadow: Bool?
    public var waitStable: Double?
    /// What a mark says, at most `RecordingMark.maximumLabel` characters.
    public var label: String?
    /// Who asked for a capture or recording, kept in the project store beside it. The app dates it when it saves the file.
    public var origin: ProjectOrigin?

    public init(_ op: Operation, window: String? = nil, duration: Double? = nil, id: String? = nil, label: String? = nil) {
        v = Self.version
        self.op = op
        self.window = window
        self.duration = duration
        self.id = id
        self.label = label
    }

    public init(_ op: Operation, target: AgentTarget, duration: Double? = nil) {
        self.init(op, window: target.window, duration: duration)
        bundleID = target.bundleID
        display = target.display
        rect = target.rect
        noShadow = target.noShadow ? true : nil
        waitStable = target.waitStable
    }

    /// What `capture` or `record` is pointed at.
    public var target: AgentTarget {
        AgentTarget(window: window, bundleID: bundleID, display: display, rect: rect, noShadow: noShadow ?? false, waitStable: waitStable)
    }

    /// The request as one line, newline included.
    public var line: Data {
        // Encoding a struct of strings and numbers can't fail.
        ((try? JSONEncoder().encode(self)) ?? Data()) + Data("\n".utf8)
    }

    /// The request in `data`, or a `.usage` error saying what's wrong with it.
    public static func decode(_ data: Data) throws(ShotCommandError) -> AgentRequest {
        guard let object = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = object else {
            throw .usage(nil, "the request isn't a JSON object")
        }
        guard object["v"]?.number == Double(version) else {
            throw .usage(nil, "this Shot speaks only version \(version) of the agent protocol; update Shot or the command line so they match")
        }
        guard let name = object["op"]?.string, let op = Operation(rawValue: name) else {
            throw .usage(nil, "unknown op \(object["op"]?.string.map { "\"\($0)\"" } ?? "(none)")")
        }
        let target = AgentTarget(
            window: object["window"]?.string,
            bundleID: object["bundleID"]?.string,
            // A display that isn't a whole number reads as 0, which `problem` refuses.
            display: object["display"]?.number.map { $0.isFinite ? Int(exactly: $0) ?? 0 : 0 },
            rect: object["rect"].map { value in
                guard case let .array(items) = value else { return [] }
                return items.map { $0.number ?? .nan }
            },
            noShadow: object["noShadow"] == .bool(true),
            waitStable: object["waitStable"]?.number
        )
        if op == .capture || op == .record, let problem = target.problem {
            throw .usage(nil, "\(op.rawValue) \(problem)")
        }
        if op == .record, target.waitStable != nil {
            throw .usage(nil, "record \(AgentTarget.waitStableIsForCapture)")
        }
        let duration = object["duration"]?.number
        if let duration, !(duration > 0 && duration <= maximumDuration) {
            throw .usage(nil, "duration must be above 0 and at most \(Int(maximumDuration)) seconds")
        }
        let label = object["label"]?.string
        if op == .mark {
            guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw .usage(nil, "mark needs a label")
            }
            guard label.count <= RecordingMark.maximumLabel else {
                throw .usage(nil, "a mark's label can be at most \(RecordingMark.maximumLabel) characters")
            }
        }
        var request = AgentRequest(op, target: target, duration: duration)
        request.id = object["id"]?.string
        request.label = label
        // An origin that doesn't read as one is left out rather than refused, since the capture doesn't depend on it.
        if let origin = object["origin"], let via = origin["via"]?.string.flatMap(ProjectOrigin.Via.init(rawValue:)) {
            request.origin = ProjectOrigin(via: via, client: origin["client"]?.string, action: origin["action"]?.string)
        }
        return request
    }
}

/// The app's answer: the result's fields, or the error with the exit code the command line ends with.
public enum AgentResponse: Equatable, Sendable {
    case success([String: JSONValue])
    case failure(ShotCommandError)

    /// The answer as one line, newline included: the result's fields with `"ok": true`, or `ok`, `code` and `message`.
    public var line: Data {
        let object: [String: JSONValue] = switch self {
        case let .success(fields):
            fields.merging(["ok": .bool(true)]) { $1 }
        case let .failure(error):
            ["ok": .bool(false), "code": .number(Double(error.exitCode)), "message": .string(error.message)]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return ((try? encoder.encode(JSONValue.object(object))) ?? Data()) + Data("\n".utf8)
    }

    public static func decode(_ data: Data) throws(ShotCommandError) -> AgentResponse {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data), case var .object(object) = value,
              let ok = object.removeValue(forKey: "ok"), case let .bool(succeeded) = ok
        else {
            throw .io("Shot's answer wasn't one it can read; update Shot or the command line so they match")
        }
        guard succeeded else {
            let code = object["code"]?.number.flatMap { $0.isFinite ? Int32(exactly: $0) : nil } ?? 70
            return .failure(ShotCommandError(exitCode: code, message: object["message"]?.string ?? "Shot gave no reason"))
        }
        return .success(object)
    }

    /// The result's fields, or the error thrown.
    public func get() throws(ShotCommandError) -> [String: JSONValue] {
        switch self {
        case let .success(fields): fields
        case let .failure(error): throw error
        }
    }
}
