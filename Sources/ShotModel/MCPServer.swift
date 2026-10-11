import Foundation

/// Any JSON value, for the parts of an MCP message whose shape the server doesn't fix.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        // Whole numbers go out without a fraction, so an id of 1 comes back as 1, not 1.0.
        case let .number(value) where value.rounded() == value && abs(value) < 1e15: try container.encode(Int64(value))
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    public var string: String? {
        if case let .string(value) = self { value } else { nil }
    }

    /// A number, or a string that reads as one, since agents sometimes quote them.
    public var number: Double? {
        switch self {
        case let .number(value): value
        case let .string(value): Double(value.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case let .object(object) = self { object[key] } else { nil }
    }
}

/// A minimal Model Context Protocol server over stdio: newline-delimited JSON-RPC 2.0 with `initialize`, `ping`,
/// `tools/list` and `tools/call`. It only parses and answers; the caller reads lines and runs the tools.
public struct MCPServer: Sendable {
    public struct Tool: Sendable {
        public var name: String
        public var description: String
        /// A JSON Schema object for the arguments.
        public var inputSchema: JSONValue

        public init(name: String, description: String, inputSchema: JSONValue) {
            self.name = name
            self.description = description
            self.inputSchema = inputSchema
        }
    }

    public enum Content: Equatable, Sendable {
        case text(String)
        /// Base64-encoded bytes.
        case image(data: String, mimeType: String)

        var json: JSONValue {
            switch self {
            case let .text(text): .object(["type": .string("text"), "text": .string(text)])
            case let .image(data, mimeType): .object(["type": .string("image"), "data": .string(data), "mimeType": .string(mimeType)])
            }
        }
    }

    /// What a tool returns. A tool that fails reports it here with `isError`, so the agent can read why and try again.
    public struct ToolResult: Equatable, Sendable {
        public var content: [Content]
        public var isError: Bool

        public init(content: [Content], isError: Bool = false) {
            self.content = content
            self.isError = isError
        }
    }

    /// JSON-RPC's own error codes.
    public enum ErrorCode: Int, Sendable {
        case parseError = -32700
        case invalidRequest = -32600
        case methodNotFound = -32601
        case invalidParams = -32602
    }

    /// The newest protocol revision this server speaks, offered to a client that asks for one it doesn't know.
    public static let protocolVersion = "2025-06-18"
    static let knownVersions: Set<String> = ["2024-11-05", "2025-03-26", protocolVersion]

    public var name: String
    public var version: String
    public var tools: [Tool]
    /// Runs the tool `name` with `arguments`, which is `.object([:])` when the client sends none.
    public var call: @Sendable (_ name: String, _ arguments: JSONValue) -> ToolResult

    public init(name: String, version: String, tools: [Tool], call: @escaping @Sendable (String, JSONValue) -> ToolResult) {
        self.name = name
        self.version = version
        self.tools = tools
        self.call = call
    }

    /// The reply to one line from the client, or `nil` when it needs none: a notification, or a blank line.
    public func respond(to line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let data = line.data(using: .utf8), let message = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return encode(error: .parseError, "Parse error", id: .null)
        }
        guard case .object = message, message["jsonrpc"]?.string == "2.0", let method = message["method"]?.string else {
            return encode(error: .invalidRequest, "Invalid request", id: message["id"] ?? .null)
        }
        // A notification, such as notifications/initialized, has no id and gets no reply.
        guard let id = message["id"] else {
            return nil
        }
        let params = message["params"] ?? .object([:])
        switch method {
        case "initialize":
            let asked = params["protocolVersion"]?.string ?? Self.protocolVersion
            return encode(result: .object([
                "protocolVersion": .string(Self.knownVersions.contains(asked) ? asked : Self.protocolVersion),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object(["name": .string(name), "version": .string(version)]),
            ]), id: id)
        case "ping":
            return encode(result: .object([:]), id: id)
        case "tools/list":
            return encode(result: .object(["tools": .array(tools.map { tool in
                .object(["name": .string(tool.name), "description": .string(tool.description), "inputSchema": tool.inputSchema])
            })]), id: id)
        case "tools/call":
            guard let requested = params["name"]?.string, let tool = Self.tool(named: requested, in: tools) else {
                return encode(error: .invalidParams, "Unknown tool: \(params["name"]?.string ?? "none given")", id: id)
            }
            var arguments = params["arguments"] ?? .object([:])
            if case .object = arguments {} else {
                arguments = .object([:])
            }
            let result = call(tool.name, arguments)
            return encode(result: .object([
                "content": .array(result.content.map(\.json)),
                "isError": .bool(result.isError),
            ]), id: id)
        default:
            return encode(error: .methodNotFound, "Method not found: \(method)", id: id)
        }
    }

    /// The tool called `name`, matched loosely: case, and `-` or a space for `_`, don't matter.
    static func tool(named name: String, in tools: [Tool]) -> Tool? {
        func folded(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        }
        let wanted = folded(name.trimmingCharacters(in: .whitespaces))
        return tools.first { folded($0.name) == wanted }
    }

    private func encode(result: JSONValue, id: JSONValue) -> String {
        encode(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
    }

    private func encode(error code: ErrorCode, _ message: String, id: JSONValue) -> String {
        encode(.object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(Double(code.rawValue)), "message": .string(message)])]))
    }

    private func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        // One message per line, so nothing may add a newline; sorted keys keep replies stable for tests.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return #"{"error":{"code":-32603,"message":"Internal error"},"id":null,"jsonrpc":"2.0"}"#
        }
        return text
    }
}
