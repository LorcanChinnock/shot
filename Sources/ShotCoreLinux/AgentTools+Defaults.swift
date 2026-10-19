import Foundation

// ShotCore's `AgentTools.live` takes the codec, canvas and video backends, which come to Linux with #656's later
// sub-issues. Until then the tools are listed, but answer that they're not on Linux yet, and `find_text`, which needs a
// Mac, isn't.

extension AgentTools {
    public static func live(
        folder: URL,
        agent: @escaping @Sendable (AgentRequest) async throws(ShotCommandError) -> [String: JSONValue] = { _ throws(ShotCommandError) in throw .unavailable("can't reach Shot from here") }
    ) -> AgentTools {
        var tools = AgentTools(folder: folder, entries: { [] }, preview: { _ in [] }, agent: agent)
        tools.unavailable = [findText]
        tools.notOnLinuxYet = Set(definitions.map(\.name)).subtracting(tools.unavailable)
        return tools
    }
}
