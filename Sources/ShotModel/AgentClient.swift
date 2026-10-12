import Foundation

/// An app that can run Shot's MCP server, and the setup Settings › Agents shows for it. Settings shows only the ones on
/// this Mac, found by the folders each makes in your home folder the first time it runs.
public enum AgentClient: CaseIterable, Sendable {
    case claudeCode
    case cursor
    case codex
    /// Any other app that reads the common `mcpServers` JSON config. Never found, only shown in place of Cursor's.
    case json

    /// What to paste to add the MCP server at `server`.
    public func setup(server: String) -> String {
        switch self {
        case .claudeCode: "claude mcp add -s user shot -- \"\(server)\" mcp"
        case .cursor, .json: #"{"mcpServers": {"shot": {"command": "\#(server)", "args": ["mcp"]}}}"#
        case .codex: "[mcp_servers.shot]\ncommand = \"\(server)\"\nargs = [\"mcp\"]"
        }
    }

    /// Paths whose presence means it's installed, relative to the home folder. Each app's own config folder, plus
    /// Cursor's app bundle, since an app that has never been opened has made no folder yet.
    var markers: [String] {
        switch self {
        case .claudeCode: [".claude", ".claude.json"]
        case .cursor: [".cursor", "Applications/Cursor.app", "/Applications/Cursor.app"]
        case .codex: [".codex"]
        case .json: []
        }
    }

    /// The ones installed for the user whose home folder is `home`.
    public static func installed(home: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Set<AgentClient> {
        Set(allCases.filter { client in
            client.markers.contains { exists($0.hasPrefix("/") ? $0 : (home as NSString).appendingPathComponent($0)) }
        })
    }

    /// The setups to show: the installed ones, then the generic JSON one unless Cursor's already covers it. With none
    /// found, every app's, since a fresh install or an unusual location shouldn't leave the card empty.
    public static func shown(installed: Set<AgentClient>) -> [AgentClient] {
        let found = [AgentClient.claudeCode, .cursor, .codex].filter(installed.contains)
        if found.isEmpty {
            return [.claudeCode, .cursor, .codex]
        }
        return found.contains(.cursor) ? found : found + [.json]
    }
}
