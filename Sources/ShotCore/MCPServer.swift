import Foundation
import Synchronization

/// A minimal Model Context Protocol server over stdio: newline-delimited JSON-RPC 2.0 with `initialize`, `ping`,
/// `tools/list` and `tools/call`. It only parses and answers; the caller reads lines and runs the tools.
public struct MCPServer: Sendable {
    public struct Tool: Sendable {
        public var name: String
        public var description: String
        /// A JSON Schema object for the arguments.
        public var inputSchema: JSONValue
        /// Sent as the `readOnlyHint` annotation, so a client can run the tool without asking, since it changes nothing.
        public var readOnly: Bool

        public init(name: String, description: String, inputSchema: JSONValue, readOnly: Bool = false) {
            self.name = name
            self.description = description
            self.inputSchema = inputSchema
            self.readOnly = readOnly
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

    /// The client, as it named itself in `initialize`.
    public struct Client: Equatable, Sendable {
        public var name: String
        public var version: String?
    }

    /// Holds `client` for a server that's otherwise a value, so copies of it share what `initialize` said.
    private final class ClientBox: Sendable {
        let client = Mutex<Client?>(nil)
    }

    /// The newest protocol revision this server speaks, offered to a client that asks for one it doesn't know.
    public static let protocolVersion = "2025-06-18"
    static let knownVersions: Set<String> = ["2024-11-05", "2025-03-26", protocolVersion]

    public var name: String
    public var version: String
    public var tools: [Tool]
    /// Runs the tool `name` with `arguments`, which is `.object([:])` when the client sends none, for `client`, as it
    /// named itself in `initialize`.
    public var call: @Sendable (_ name: String, _ arguments: JSONValue, _ client: Client?) async -> ToolResult
    private let clientBox = ClientBox()

    /// The client from `clientInfo` in `initialize`, for a project's provenance; `nil` until then, or when it sent none.
    public var client: Client? { clientBox.client.withLock { $0 } }

    public init(name: String, version: String, tools: [Tool], call: @escaping @Sendable (String, JSONValue, Client?) async -> ToolResult) {
        self.name = name
        self.version = version
        self.tools = tools
        self.call = call
    }

    /// The reply to one line from the client, or `nil` when it needs none: a notification, or a blank line.
    public func respond(to line: String) async -> String? {
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
            let info = params["clientInfo"]
            let client = info?["name"]?.string.flatMap { $0.isEmpty ? nil : Client(name: $0, version: info?["version"]?.string) }
            clientBox.client.withLock { $0 = client }
            return encode(result: .object([
                "protocolVersion": .string(Self.knownVersions.contains(asked) ? asked : Self.protocolVersion),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object(["name": .string(name), "version": .string(version)]),
            ]), id: id)
        case "ping":
            return encode(result: .object([:]), id: id)
        case "tools/list":
            return encode(result: .object(["tools": .array(tools.map { tool in
                var listed: [String: JSONValue] = ["name": .string(tool.name), "description": .string(tool.description), "inputSchema": tool.inputSchema]
                if tool.readOnly {
                    listed["annotations"] = .object(["readOnlyHint": .bool(true)])
                }
                return .object(listed)
            })]), id: id)
        case "tools/call":
            guard let requested = params["name"]?.string, let tool = Self.tool(named: requested, in: tools) else {
                return encode(error: .invalidParams, "Unknown tool: \(params["name"]?.string ?? "none given")", id: id)
            }
            var arguments = params["arguments"] ?? .object([:])
            if case .object = arguments {} else {
                arguments = .object([:])
            }
            let result = await call(tool.name, arguments, client)
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
