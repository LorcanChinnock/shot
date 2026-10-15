import Foundation

/// An app that can run Shot's MCP server, and the setup Settings › Agents shows for it. Settings shows only the ones on
/// this Mac, found by the folders each makes in your home folder the first time it runs, or by its app. General
/// assistants come first, then coding agents.
public enum AgentClient: CaseIterable, Sendable {
    /// The Claude desktop app.
    case claude
    case lmStudio
    case raycast
    case claudeCode
    case codex
    case cursor
    case vsCode
    case gemini
    case windsurf
    case zed
    /// Any other app that reads the common `mcpServers` JSON config. Never found, always shown last.
    case json

    /// How Install adds the server.
    public enum Install: Equatable, Sendable {
        /// Opens a link the agent handles, which asks you to confirm.
        case link(String)
        /// Runs the agent's own command line tool, once per command line in turn: the program's name, then its
        /// arguments.
        case command([[String]])
        /// Adds the server to the JSON config file at this path, relative to the home folder, under `key`.
        case config(path: String, key: String)
    }

    /// Whether the server is set up in an agent.
    public enum Status: Equatable, Sendable {
        /// Shot can't read the agent's config, so it can't tell.
        case unknown
        case missing
        case installed
        /// Set up, but pointing at a `shot-cli` that isn't this one, such as a copy of Shot that has since moved.
        case stale
    }

    /// What to paste to add the MCP server at `server`, under `name`.
    public func setup(server: String, name: String) -> String {
        switch self {
        case .claude, .lmStudio, .raycast, .cursor, .windsurf, .json: Self.json(key: "mcpServers", name: name, server: server)
        case .vsCode: Self.json(key: "servers", name: name, server: server)
        case .zed: Self.json(key: "context_servers", name: name, server: server)
        case .claudeCode, .codex, .gemini: (install(server: server, name: name).flatMap(\.commands)?.last ?? []).map(Self.shellQuoted).joined(separator: " ")
        }
    }

    /// How Install adds the server at `server` under `name`: the agent's own link or tool where it has one, so it can
    /// confirm and knows its format, or else an edit of its config. Nil where Shot can only offer Copy: Zed's settings
    /// keep comments that a JSON round trip would lose, and the generic setup has no app to install into. `replacing`
    /// is for a server that's already set up under `name`, which Claude Code won't add over, so it's removed first;
    /// the other tools replace it themselves.
    public func install(server: String, name: String, replacing: Bool = false) -> Install? {
        let entry: [String: Any] = ["command": server, "args": ["mcp"]]
        switch self {
        case .claude: return .config(path: Self.claudeConfig, key: "mcpServers")
        case .windsurf: return .config(path: ".codeium/windsurf/mcp_config.json", key: "mcpServers")
        case .lmStudio: return .link("lmstudio://add_mcp?name=\(Self.queryEncoded(name))&config=\(Self.queryEncoded(Self.compact(entry).base64EncodedString()))")
        case .raycast: return .link("raycast://mcp/install?\(Self.queryEncoded(String(decoding: Self.compact(["name": name, "type": "stdio", "command": server, "args": ["mcp"]]), as: UTF8.self)))")
        case .cursor: return .link("cursor://anysphere.cursor-deeplink/mcp/install?name=\(Self.queryEncoded(name))&config=\(Self.queryEncoded(Self.compact(entry).base64EncodedString()))")
        case .vsCode: return .link("vscode:mcp/install?\(Self.queryEncoded(String(decoding: Self.compact(["name": name, "command": server, "args": ["mcp"]]), as: UTF8.self)))")
        case .claudeCode: return .command((replacing ? [["claude", "mcp", "remove", "-s", "user", name]] : []) + [["claude", "mcp", "add", "-s", "user", name, "--", server, "mcp"]])
        case .codex: return .command([["codex", "mcp", "add", name, "--", server, "mcp"]])
        case .gemini: return .command([["gemini", "mcp", "add", "-s", "user", name, server, "mcp"]])
        case .zed, .json: return nil
        }
    }

    /// Paths whose presence means it's installed, relative to the home folder unless absolute. Each app's own config
    /// folder, plus its app bundle where it has one, since an app that has never been opened has made no folder yet.
    var markers: [String] {
        switch self {
        case .claude: ["Library/Application Support/Claude"] + Self.app("Claude")
        case .lmStudio: [".lmstudio"] + Self.app("LM Studio")
        case .raycast: Self.app("Raycast")
        case .claudeCode: [".claude", ".claude.json"]
        case .codex: [".codex"]
        case .cursor: [".cursor"] + Self.app("Cursor")
        case .vsCode: [".vscode"] + Self.app("Visual Studio Code")
        case .gemini: [".gemini"]
        case .windsurf: [".codeium/windsurf"] + Self.app("Windsurf")
        case .zed: [".config/zed"] + Self.app("Zed")
        case .json: []
        }
    }

    /// The config file that holds the server, relative to the home folder, and the key its servers are under. Nil
    /// where Shot can't read it: Raycast's isn't documented, and Zed's has comments.
    var config: (path: String, key: String)? {
        switch self {
        case .claude: (Self.claudeConfig, "mcpServers")
        case .lmStudio: (".lmstudio/mcp.json", "mcpServers")
        case .claudeCode: (".claude.json", "mcpServers")
        case .codex: (".codex/config.toml", "mcp_servers")
        case .cursor: (".cursor/mcp.json", "mcpServers")
        case .vsCode: ("Library/Application Support/Code/User/mcp.json", "servers")
        case .gemini: (".gemini/settings.json", "mcpServers")
        case .windsurf: (".codeium/windsurf/mcp_config.json", "mcpServers")
        case .raycast, .zed, .json: nil
        }
    }

    /// Whether the server at `server` is set up under `name`, read from the agent's config in the home folder `home`.
    public func status(server: String, name: String, home: String, read: (String) -> Data? = { FileManager.default.contents(atPath: $0) }) -> Status {
        guard let config else {
            return .unknown
        }
        guard let data = read((home as NSString).appendingPathComponent(config.path)) else {
            return .missing
        }
        let command: String?
        if self == .codex {
            command = Self.tomlCommand(String(decoding: data, as: UTF8.self), key: config.key, name: name)
        } else {
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unknown
            }
            command = ((root[config.key] as? [String: Any])?[name] as? [String: Any])?["command"] as? String
        }
        guard let command else {
            return .missing
        }
        return command == server ? .installed : .stale
    }

    /// The ones installed for the user whose home folder is `home`.
    public static func installed(home: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Set<AgentClient> {
        Set(allCases.filter { client in
            client.markers.contains { exists($0.hasPrefix("/") ? $0 : (home as NSString).appendingPathComponent($0)) }
        })
    }

    /// The setups to show: the installed ones, then the generic JSON one. With none found, every app's, since a fresh
    /// install or an unusual location shouldn't leave the card empty.
    public static func shown(installed: Set<AgentClient>) -> [AgentClient] {
        let apps = allCases.filter { $0 != .json }
        let found = apps.filter(installed.contains)
        return (found.isEmpty ? apps : found) + [.json]
    }

    /// `config` with the server at `server` set under `key` › `name`, keeping every other key. Nil or empty `config`
    /// starts a new file. Throws for a file that isn't a JSON object, which must be left as it is.
    public static func adding(server: String, name: String, key: String, to config: Data?) throws -> Data {
        var root: [String: Any] = [:]
        if let config, !String(decoding: config, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let object = try JSONSerialization.jsonObject(with: config) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            root = object
        }
        guard root[key] == nil || root[key] is [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var servers = root[key] as? [String: Any] ?? [:]
        servers[name] = ["command": server, "args": ["mcp"]]
        root[key] = servers
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static let claudeConfig = "Library/Application Support/Claude/claude_desktop_config.json"

    private static func app(_ name: String) -> [String] {
        ["/Applications/\(name).app", "Applications/\(name).app"]
    }

    private static func json(key: String, name: String, server: String) -> String {
        #"{"\#(key)": {"\#(escaped(name))": {"command": "\#(escaped(server))", "args": ["mcp"]}}}"#
    }

    /// `text` escaped to sit inside a JSON string.
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func compact(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    /// `text` percent-encoded to sit in a URL's query, where `&`, `=`, `+` and `/` would otherwise be read as syntax.
    private static func queryEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? text
    }

    /// `argument` as a shell reads it, quoted only when it has to be.
    private static func shellQuoted(_ argument: String) -> String {
        argument.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:".contains($0) } ? argument : "\"\(argument.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// The `command` in the TOML table `[key.name]`, such as `[mcp_servers.shot]`, read line by line, which is enough
    /// for the basic strings Codex writes.
    static func tomlCommand(_ toml: String, key: String, name: String) -> String? {
        let headers = ["[\(key).\(name)]", "[\(key).\"\(name)\"]"]
        var inside = false
        for line in toml.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("[") {
                inside = headers.contains(line)
                continue
            }
            guard inside, line.hasPrefix("command") else {
                continue
            }
            let value = line.drop { $0 != "=" }.dropFirst().trimmingCharacters(in: .whitespaces)
            guard value.count >= 2, value.first == "\"", value.last == "\"" else {
                return nil
            }
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        }
        return nil
    }
}

extension AgentClient.Install {
    /// The command lines, for a tool that installs through them.
    var commands: [[String]]? {
        if case let .command(commands) = self { commands } else { nil }
    }
}
