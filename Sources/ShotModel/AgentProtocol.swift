import Foundation

/// What the `shot` command line and the MCP server ask the running app over its agent socket: one JSON line per
/// connection, answered by one `AgentResponse` line. Here, with no socket, so every message is tested on Linux.
public struct AgentRequest: Codable, Equatable, Sendable {
    /// The protocol's version; a request with another is refused, so an old app never half-understands a new one.
    public static let version = 1

    public enum Operation: String, Codable, Sendable {
        /// A screenshot of `window`.
        case capture
        /// Whether the app is capturing or recording.
        case status
    }

    public var v: Int
    public var op: Operation
    /// Words from the window's title or app, as `WindowMatch` reads them.
    public var window: String?

    public init(_ op: Operation, window: String? = nil) {
        v = Self.version
        self.op = op
        self.window = window
    }

    /// The request as one line, newline included.
    public var line: Data {
        // Encoding a struct of strings and an int can't fail.
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
        let window = object["window"]?.string
        if op == .capture, (window ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            throw .usage(nil, "capture needs a window")
        }
        return AgentRequest(op, window: window)
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
