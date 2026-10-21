import Foundation

// ShotCore's calls that code images, draw or read video take their backends. On Linux they're PNGJPEGCodec,
// CairoCanvas and ffmpeg's FFmpegReader, FFmpegAssembler and FFmpegWriter, so these give ShotCLI and the tests each call
// without them, as ShotCoreApple's do on a Mac.

extension ProjectStore {
    public init(folder: URL) {
        self.init(folder: folder, codec: PNGJPEGCodec())
    }

    /// The store in `$XDG_DATA_HOME/<bundle ID>/Projects`, `~/.local/share` when it isn't set.
    public init(bundleID: String) {
        self.init(bundleID: bundleID, codec: PNGJPEGCodec())
    }
}

extension ShotCommands {
    /// Runs the media commands. Those that record or pick answer `ShotCommandError.notOnLinuxYet`.
    public static func run(_ command: ShotCommand, projects: ProjectStore? = nil, origin: ProjectOrigin? = nil) async throws(ShotCommandError) -> JSONValue {
        guard Doctor.linuxCommands.contains(command.name) || command.name == "text" else {
            throw .notOnLinuxYet
        }
        return try await run(
            command, projects: projects, origin: origin, codec: PNGJPEGCodec(), canvasType: CairoCanvas.self, reader: FFmpegReader(), assembler: FFmpegAssembler(),
            writer: FFmpegWriter()
        )
    }
}
