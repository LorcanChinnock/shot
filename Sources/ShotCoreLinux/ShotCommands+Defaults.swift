import Foundation

// ShotCore's calls that code images, draw or read video take their backends. On Linux they're PNGJPEGCodec,
// CairoCanvas and, until ffmpeg's come with #656, NoVideo, so these give ShotCLI and the tests each call without them,
// as ShotCoreApple's do on a Mac.

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
    /// Runs the image commands. Those that read video, `info` and `edit` on one included, answer
    /// `ShotCommandError.notOnLinuxYet`.
    public static func run(_ command: ShotCommand, projects: ProjectStore? = nil, origin: ProjectOrigin? = nil) async throws(ShotCommandError) -> JSONValue {
        guard Doctor.linuxCommands.contains(command.name) || command.name == "text", !readsVideo(command) else {
            throw .notOnLinuxYet
        }
        return try await run(command, projects: projects, origin: origin, codec: PNGJPEGCodec(), canvasType: CairoCanvas.self, reader: NoVideo(), assembler: NoVideo(), writer: NoVideo())
    }

    /// Whether `command` reads a video: an `info` or `edit` of a file with a video's extension, or a video edit.
    static func readsVideo(_ command: ShotCommand) -> Bool {
        let input: String
        switch command {
        case let .info(path):
            input = path
        case let .edit(options):
            if case .video = options.spec {
                return true
            }
            input = options.input
        default:
            return false
        }
        return GalleryKind(fileExtension: URL(fileURLWithPath: input).pathExtension) == .video
    }
}
