import Foundation

// ShotCore's `AgentTools.live` with Linux's backends: the tools that read captures and make images from them run, on
// PNGJPEGCodec and CairoCanvas. Those that capture, record or read video are listed, but answer that they're not on
// Linux yet, and `find_text`, which needs a Mac, isn't.

extension AgentTools {
    /// The tools reading the captures in `folder`, keeping what they make in `projects`. A recording in the folder is
    /// listed, with no preview.
    public static func live(
        folder: URL,
        projects: ProjectStore? = nil,
        agent: @escaping @Sendable (AgentRequest) async throws(ShotCommandError) -> [String: JSONValue] = { _ throws(ShotCommandError) in throw .unavailable("can't reach Shot from here") }
    ) -> AgentTools {
        var tools = live(
            folder: folder, projects: projects, codec: PNGJPEGCodec(), canvasType: CairoCanvas.self, reader: NoVideo(), assembler: NoVideo(), writer: NoVideo(), agent: agent
        )
        let preview = tools.preview
        tools.preview = { entry in
            entry.isVideo ? [.text("Previews of recordings are \(ShotCommandError.notOnLinuxYet.message).")] : await preview(entry)
        }
        tools.notOnLinuxYet = Set(Doctor.notOnLinuxYetTools)
        return tools
    }
}
