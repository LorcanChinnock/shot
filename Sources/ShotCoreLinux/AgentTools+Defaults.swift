import Foundation

// ShotCore's `AgentTools.live` with Linux's backends: the tools that read captures and make images and videos from them
// run, on PNGJPEGCodec, CairoCanvas and ffmpeg, and those that capture send `agent` to `shot serve`. Those that record or
// pick are listed, but answer that they're not on Linux yet, and `find_text`, which needs a Mac, isn't.

extension AgentTools {
    /// The tools reading the captures in `folder`, keeping what they make in `projects`. `marks` is the store of the
    /// marks agents stamped on their recordings, which `get_frames` shows.
    public static func live(
        folder: URL,
        marks: URL? = nil,
        projects: ProjectStore? = nil,
        agent: @escaping @Sendable (AgentRequest) async throws(ShotCommandError) -> [String: JSONValue] = { _ throws(ShotCommandError) in throw .unavailable("can't reach Shot from here") }
    ) -> AgentTools {
        var tools = live(
            folder: folder, marks: marks, projects: projects, codec: PNGJPEGCodec(), canvasType: CairoCanvas.self, reader: FFmpegReader(), assembler: FFmpegAssembler(),
            writer: FFmpegWriter(), agent: agent
        )
        tools.notOnLinuxYet = Set(Doctor.notOnLinuxYetTools)
        return tools
    }
}
