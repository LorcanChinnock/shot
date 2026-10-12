import Foundation
import Testing
@testable import ShotModel

private func installed(_ paths: Set<String>) -> Set<AgentClient> {
    AgentClient.installed(home: "/Users/me", exists: paths.contains)
}

@Test func eachAgentIsFoundByTheFolderItMakesInHome() {
    #expect(installed([]) == [])
    #expect(installed(["/Users/me/.claude"]) == [.claudeCode])
    #expect(installed(["/Users/me/.claude.json"]) == [.claudeCode])
    #expect(installed(["/Users/me/.cursor"]) == [.cursor])
    #expect(installed(["/Users/me/.codex"]) == [.codex])
    #expect(installed(["/Users/me/.claude", "/Users/me/.codex"]) == [.claudeCode, .codex])
}

@Test func cursorIsFoundByItsAppBeforeItsEverOpened() {
    #expect(installed(["/Applications/Cursor.app"]) == [.cursor])
    #expect(installed(["/Users/me/Applications/Cursor.app"]) == [.cursor])
}

@Test func onlyInstalledAgentsAreShownWithTheGenericJSONLast() {
    #expect(AgentClient.shown(installed: [.claudeCode]) == [.claudeCode, .json])
    #expect(AgentClient.shown(installed: [.codex, .claudeCode]) == [.claudeCode, .codex, .json])
}

@Test func cursorsSetupStandsInForTheGenericJSON() {
    #expect(AgentClient.shown(installed: [.cursor]) == [.cursor])
    #expect(AgentClient.shown(installed: [.claudeCode, .cursor, .codex]) == [.claudeCode, .cursor, .codex])
}

@Test func withNoAgentFoundEverySetupIsShown() {
    #expect(AgentClient.shown(installed: []) == [.claudeCode, .cursor, .codex])
}

@Test func eachSetupNamesTheServerPath() {
    let server = "/Applications/Shot Dev.app/Contents/MacOS/shot-cli"
    #expect(AgentClient.claudeCode.setup(server: server) == #"claude mcp add -s user shot -- "/Applications/Shot Dev.app/Contents/MacOS/shot-cli" mcp"#)
    #expect(AgentClient.cursor.setup(server: server) == #"{"mcpServers": {"shot": {"command": "/Applications/Shot Dev.app/Contents/MacOS/shot-cli", "args": ["mcp"]}}}"#)
    #expect(AgentClient.json.setup(server: server) == AgentClient.cursor.setup(server: server))
    #expect(AgentClient.codex.setup(server: server) == "[mcp_servers.shot]\ncommand = \"/Applications/Shot Dev.app/Contents/MacOS/shot-cli\"\nargs = [\"mcp\"]")
}
