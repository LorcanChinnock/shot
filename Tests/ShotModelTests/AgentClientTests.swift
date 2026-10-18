import Foundation
import Testing
@testable import ShotModel

private let server = "/Applications/Shot Dev.app/Contents/MacOS/shot-cli"

private func installed(_ paths: Set<String>) -> Set<AgentClient> {
    AgentClient.installed(home: "/Users/me", exists: paths.contains)
}

private func status(_ client: AgentClient, _ files: [String: String]) -> AgentClient.Status {
    client.status(server: server, name: "shot", home: "/Users/me") { files[$0].map { Data($0.utf8) } }
}

private func json(_ data: Data) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

@Test func eachAgentIsFoundByTheFolderItMakesInHome() {
    #expect(installed([]) == [])
    #expect(installed(["/Users/me/.claude"]) == [.claudeCode])
    #expect(installed(["/Users/me/.claude.json"]) == [.claudeCode])
    #expect(installed(["/Users/me/Library/Application Support/Claude"]) == [.claude])
    #expect(installed(["/Users/me/.lmstudio"]) == [.lmStudio])
    #expect(installed(["/Users/me/.cursor"]) == [.cursor])
    #expect(installed(["/Users/me/.codex"]) == [.codex])
    #expect(installed(["/Users/me/.vscode"]) == [.vsCode])
    #expect(installed(["/Users/me/.gemini"]) == [.gemini])
    #expect(installed(["/Users/me/.config/devin"]) == [.devin])
    #expect(installed(["/Users/me/.codeium/windsurf"]) == [.devin])
    #expect(installed(["/Users/me/.config/zed"]) == [.zed])
    #expect(installed(["/Users/me/.claude", "/Users/me/.codex"]) == [.claudeCode, .codex])
}

@Test func appsAreFoundBeforeTheyreEverOpened() {
    #expect(installed(["/Applications/Cursor.app"]) == [.cursor])
    #expect(installed(["/Users/me/Applications/Cursor.app"]) == [.cursor])
    #expect(installed(["/Applications/Claude.app"]) == [.claude])
    #expect(installed(["/Applications/Raycast.app"]) == [.raycast])
    #expect(installed(["/Applications/LM Studio.app"]) == [.lmStudio])
    #expect(installed(["/Applications/Visual Studio Code.app"]) == [.vsCode])
    #expect(installed(["/Applications/Devin.app"]) == [.devin])
    #expect(installed(["/Applications/Windsurf.app"]) == [.devin])
}

@Test func onlyInstalledAgentsAreShownAssistantsFirstWithTheGenericJSONLast() {
    #expect(AgentClient.shown(installed: [.claudeCode]) == [.claudeCode, .json])
    #expect(AgentClient.shown(installed: [.codex, .claudeCode, .claude]) == [.claude, .claudeCode, .codex, .json])
    #expect(AgentClient.shown(installed: [.cursor]) == [.cursor, .json])
}

@Test func withNoAgentFoundEverySetupIsShown() {
    #expect(AgentClient.shown(installed: []) == [.claude, .lmStudio, .raycast, .claudeCode, .codex, .cursor, .vsCode, .gemini, .devin, .zed, .json])
}

@Test func eachSetupNamesTheServerPath() {
    let mcpServers = #"{"mcpServers": {"shot": {"command": "/Applications/Shot Dev.app/Contents/MacOS/shot-cli", "args": ["mcp"]}}}"#
    #expect(AgentClient.claudeCode.setup(server: server, name: "shot") == #"claude mcp add -s user shot -- "/Applications/Shot Dev.app/Contents/MacOS/shot-cli" mcp"#)
    #expect(AgentClient.codex.setup(server: server, name: "shot") == #"codex mcp add shot -- "/Applications/Shot Dev.app/Contents/MacOS/shot-cli" mcp"#)
    #expect(AgentClient.gemini.setup(server: server, name: "shot") == #"gemini mcp add -s user shot "/Applications/Shot Dev.app/Contents/MacOS/shot-cli" mcp"#)
    for client in [AgentClient.claude, .lmStudio, .raycast, .cursor, .devin, .json] {
        #expect(client.setup(server: server, name: "shot") == mcpServers)
    }
    #expect(AgentClient.vsCode.setup(server: server, name: "shot") == #"{"servers": {"shot": {"command": "/Applications/Shot Dev.app/Contents/MacOS/shot-cli", "args": ["mcp"]}}}"#)
    #expect(AgentClient.zed.setup(server: server, name: "shot") == #"{"context_servers": {"shot": {"command": "/Applications/Shot Dev.app/Contents/MacOS/shot-cli", "args": ["mcp"]}}}"#)
}

@Test func aDevBuildsSetupUsesItsOwnName() {
    #expect(AgentClient.claudeCode.setup(server: server, name: "shot-dev").contains(" shot-dev -- "))
    #expect(AgentClient.cursor.setup(server: server, name: "shot-dev").contains(#""shot-dev": {"#))
}

@Test func setupsThatPasteIntoJSONEscapeThePath() {
    let setup = AgentClient.json.setup(server: #"/Users/a "b"/shot-cli"#, name: "shot")
    let servers = json(Data(setup.utf8))?["mcpServers"] as? [String: Any]
    #expect((servers?["shot"] as? [String: Any])?["command"] as? String == #"/Users/a "b"/shot-cli"#)
}

@Test func toolsInstallWithTheirOwnCommandLine() {
    #expect(AgentClient.claudeCode.install(server: server, name: "shot") == .command([["claude", "mcp", "add", "-s", "user", "shot", "--", server, "mcp"]]))
    #expect(AgentClient.codex.install(server: server, name: "shot") == .command([["codex", "mcp", "add", "shot", "--", server, "mcp"]]))
    #expect(AgentClient.gemini.install(server: server, name: "shot") == .command([["gemini", "mcp", "add", "-s", "user", "shot", server, "mcp"]]))
}

@Test func claudeCodeRemovesAStaleServerBeforeAddingItAgain() {
    #expect(AgentClient.claudeCode.install(server: server, name: "shot", replacing: true) == .command([
        ["claude", "mcp", "remove", "-s", "user", "shot"],
        ["claude", "mcp", "add", "-s", "user", "shot", "--", server, "mcp"],
    ]))
    // Codex and Gemini CLI replace a server that's already there.
    #expect(AgentClient.codex.install(server: server, name: "shot", replacing: true) == AgentClient.codex.install(server: server, name: "shot"))
    #expect(AgentClient.gemini.install(server: server, name: "shot", replacing: true) == AgentClient.gemini.install(server: server, name: "shot"))
}

@Test func appsWithoutALinkOrToolInstallByEditingTheirConfig() {
    #expect(AgentClient.claude.install(server: server, name: "shot") == .config(paths: ["Library/Application Support/Claude/claude_desktop_config.json"], key: "mcpServers"))
    #expect(AgentClient.devin.install(server: server, name: "shot") == .config(paths: [".config/devin/mcp_config.json", ".codeium/windsurf/mcp_config.json"], key: "mcpServers"))
    #expect(AgentClient.zed.install(server: server, name: "shot") == nil)
    #expect(AgentClient.json.install(server: server, name: "shot") == nil)
}

/// The query value of `name` in `link`, decoded.
private func query(_ link: String, _ name: String) -> String? {
    URLComponents(string: link)?.queryItems?.first { $0.name == name }?.value
}

@Test func cursorAndLMStudioLinksCarryTheEntryInBase64() throws {
    for client in [AgentClient.cursor, .lmStudio] {
        guard case let .link(link) = client.install(server: server, name: "shot") else {
            Issue.record("\(client) should install with a link")
            continue
        }
        #expect(query(link, "name") == "shot")
        let config = try #require(query(link, "config").flatMap { Data(base64Encoded: $0) }.flatMap(json))
        #expect(config["command"] as? String == server)
        #expect(config["args"] as? [String] == ["mcp"])
    }
    guard case let .link(cursor) = AgentClient.cursor.install(server: server, name: "shot"), case let .link(lmStudio) = AgentClient.lmStudio.install(server: server, name: "shot") else {
        return
    }
    #expect(cursor.hasPrefix("cursor://anysphere.cursor-deeplink/mcp/install?"))
    #expect(lmStudio.hasPrefix("lmstudio://add_mcp?"))
}

@Test func vsCodeAndRaycastLinksCarryTheEntryAsJSON() throws {
    for (client, prefix) in [(AgentClient.vsCode, "vscode:mcp/install?"), (.raycast, "raycast://mcp/install?")] {
        guard case let .link(link) = client.install(server: server, name: "shot") else {
            Issue.record("\(client) should install with a link")
            continue
        }
        #expect(link.hasPrefix(prefix))
        let config = try #require(link.dropFirst(prefix.count).removingPercentEncoding.flatMap { json(Data($0.utf8)) })
        #expect(config["name"] as? String == "shot")
        #expect(config["command"] as? String == server)
        #expect(config["args"] as? [String] == ["mcp"])
        #expect(!link.contains(" "))
    }
}

@Test func addingTheServerKeepsEveryOtherKey() throws {
    let config = Data(#"{"preferences": {"theme": "dark"}, "mcpServers": {"other": {"command": "x"}}}"#.utf8)
    let result = try #require(json(try AgentClient.adding(server: server, name: "shot", key: "mcpServers", to: config)))
    #expect((result["preferences"] as? [String: Any])?["theme"] as? String == "dark")
    let servers = try #require(result["mcpServers"] as? [String: Any])
    #expect((servers["other"] as? [String: Any])?["command"] as? String == "x")
    #expect((servers["shot"] as? [String: Any])?["command"] as? String == server)
    #expect((servers["shot"] as? [String: Any])?["args"] as? [String] == ["mcp"])
}

@Test func addingTheServerReplacesOnlyItsOwnEntry() throws {
    let config = Data(#"{"mcpServers": {"shot": {"command": "/old/shot-cli", "args": ["mcp"], "env": {"A": "1"}}}}"#.utf8)
    let servers = try #require(json(try AgentClient.adding(server: server, name: "shot", key: "mcpServers", to: config))?["mcpServers"] as? [String: Any])
    let entry = try #require(servers["shot"] as? [String: Any])
    #expect(Set(entry.keys) == ["command", "args"])
    #expect(entry["command"] as? String == server)
    #expect(entry["args"] as? [String] == ["mcp"])
}

@Test func addingTheServerStartsAMissingOrEmptyFile() throws {
    for config in [nil, Data(), Data(" \n".utf8)] {
        let result = try #require(json(try AgentClient.adding(server: server, name: "shot", key: "mcpServers", to: config)))
        #expect(((result["mcpServers"] as? [String: Any])?["shot"] as? [String: Any])?["command"] as? String == server)
    }
}

@Test func aConfigThatDoesntParseIsNeverWritten() {
    for config in [#"{"mcpServers": {"#, "// a comment\n{}", "[1, 2]", #"{"mcpServers": []}"#] {
        #expect(throws: (any Error).self) { try AgentClient.adding(server: server, name: "shot", key: "mcpServers", to: Data(config.utf8)) }
    }
}

@Test func statusComesFromTheAgentsConfig() {
    let claude = "/Users/me/Library/Application Support/Claude/claude_desktop_config.json"
    #expect(status(.claude, [:]) == .missing)
    #expect(status(.claude, [claude: #"{"preferences": {}}"#]) == .missing)
    #expect(status(.claude, [claude: #"{"mcpServers": {"shot": {"command": "\#(server)"}}}"#]) == .installed)
    #expect(status(.claude, [claude: #"{"mcpServers": {"shot": {"command": "/Old/Shot.app/Contents/MacOS/shot-cli"}}}"#]) == .stale)
    #expect(status(.claude, [claude: "not json"]) == .unknown)
    #expect(status(.vsCode, ["/Users/me/Library/Application Support/Code/User/mcp.json": #"{"servers": {"shot": {"command": "\#(server)"}}}"#]) == .installed)
    #expect(status(.claudeCode, ["/Users/me/.claude.json": #"{"mcpServers": {"shot": {"command": "\#(server)"}}}"#]) == .installed)
}

@Test func aConfigInstallWritesTheFirstFileThatExistsOrElseStartsTheFirst() {
    let paths = [".config/devin/mcp_config.json", ".codeium/windsurf/mcp_config.json"]
    let devin = "/Users/me/.config/devin/mcp_config.json", windsurf = "/Users/me/.codeium/windsurf/mcp_config.json"
    #expect(AgentClient.file(among: paths, home: "/Users/me") { [devin, windsurf].contains($0) } == devin)
    // Before Devin moves the Windsurf config, the old file is the one it reads.
    #expect(AgentClient.file(among: paths, home: "/Users/me") { $0 == windsurf } == windsurf)
    #expect(AgentClient.file(among: paths, home: "/Users/me") { _ in false } == devin)
}

@Test func devinStatusComesFromItsNewConfigOnceItHasOne() {
    let devin = "/Users/me/.config/devin/mcp_config.json", windsurf = "/Users/me/.codeium/windsurf/mcp_config.json"
    let current = #"{"mcpServers": {"shot": {"command": "\#(server)"}}}"#, old = #"{"mcpServers": {"shot": {"command": "/Old/Shot.app/Contents/MacOS/shot-cli"}}}"#
    #expect(status(.devin, [windsurf: current]) == .installed)
    #expect(status(.devin, [devin: current]) == .installed)
    // Devin reads only the new file once it has copied the old one there.
    #expect(status(.devin, [devin: old, windsurf: current]) == .stale)
    #expect(status(.devin, [devin: #"{"mcpServers": {}}"#, windsurf: current]) == .missing)
}

@Test func statusIsUnknownWhereShotCantReadTheConfig() {
    #expect(status(.raycast, [:]) == .unknown)
    #expect(status(.zed, [:]) == .unknown)
    #expect(status(.json, [:]) == .unknown)
}

@Test func codexStatusComesFromItsTOMLTable() {
    let path = "/Users/me/.codex/config.toml"
    #expect(status(.codex, [path: "model = \"o3\"\n"]) == .missing)
    #expect(status(.codex, [path: "[mcp_servers.other]\ncommand = \"\(server)\"\n"]) == .missing)
    #expect(status(.codex, [path: "model = \"o3\"\n\n[mcp_servers.shot]\ncommand = \"\(server)\"\nargs = [\"mcp\"]\n"]) == .installed)
    #expect(status(.codex, [path: "[mcp_servers.\"shot\"]\n  command = \"/old/shot-cli\"\n"]) == .stale)
    #expect(status(.codex, [path: "[mcp_servers.shot]\nargs = [\"mcp\"]\n[other]\ncommand = \"\(server)\"\n"]) == .missing)
}
