import Foundation

extension Doctor {
    /// What `shot doctor` checks on Linux, where `shot serve` answers agents rather than an app: the session, the desktop
    /// portal on Wayland, Let agents capture and record, `shot serve`, ffmpeg, what runs so far, what's left out by design, the emoji font, and the capture
    /// folder.
    public struct LinuxFacts: Equatable, Sendable {
        public var version: String
        /// The settings file the command reads.
        public var settingsFile: String
        /// `XDG_SESSION_TYPE`, such as `x11` or `wayland`.
        public var sessionType: String?
        public var agentCapture: Bool
        /// The socket `shot serve` answers on.
        public var socketPath: String
        /// Whether something accepts connections on the socket.
        public var listening: Bool
        /// `shot serve`'s answer to a status request, or why it gave none, when it's listening.
        public var status: Result<[String: JSONValue], ShotCommandError>?
        public var folder: String
        public var folderExists: Bool
        /// Why the folder couldn't be listed, or `nil` when it could.
        public var folderError: String?
        /// How many captures the folder holds, when it could be listed.
        public var captures: Int
        /// Whether a font that draws emoji in colour is installed.
        public var colorEmoji: Bool
        /// The version of the desktop portal's Screenshot interface, or why there's none, in a Wayland session; `nil` in
        /// any other.
        public var screenshotPortal: Result<Int, ShotCommandError>?
        /// The ffmpeg and ffprobe that read, trim, join and export video.
        public var ffmpeg: FFmpegFacts?

        public init(
            version: String, settingsFile: String, sessionType: String?, agentCapture: Bool, socketPath: String, listening: Bool,
            status: Result<[String: JSONValue], ShotCommandError>?, folder: String, folderExists: Bool, folderError: String?, captures: Int,
            colorEmoji: Bool, screenshotPortal: Result<Int, ShotCommandError>? = nil, ffmpeg: FFmpegFacts? = nil
        ) {
            self.version = version
            self.settingsFile = settingsFile
            self.sessionType = sessionType
            self.agentCapture = agentCapture
            self.socketPath = socketPath
            self.listening = listening
            self.status = status
            self.folder = folder
            self.folderExists = folderExists
            self.folderError = folderError
            self.captures = captures
            self.colorEmoji = colorEmoji
            self.screenshotPortal = screenshotPortal
            self.ffmpeg = ffmpeg
        }
    }

    /// Where `ffmpeg` and `ffprobe` are, when they're found, ffmpeg's version, and the encoders it has.
    public struct FFmpegFacts: Equatable, Sendable {
        public var ffmpeg: String?
        public var ffprobe: String?
        public var version: String?
        public var encoders: Set<String>

        public init(ffmpeg: String?, ffprobe: String?, version: String? = nil, encoders: Set<String> = []) {
            self.ffmpeg = ffmpeg
            self.ffprobe = ffprobe
            self.version = version
            self.encoders = encoders
        }
    }

    /// The commands that run on Linux so far: the image and video commands, those that read the capture folder, and
    /// `capture` and `windows`, which ask `shot serve`. `text`, and `redact --detect`, run only to say they need a Mac.
    /// The rest record or pick, and answer `ShotCommandError.notOnLinuxYet`.
    public static let linuxCommands = [
        "version", "help", "doctor", "mcp", "serve", "settings", "info", "annotate", "redact", "crop", "diff", "edit", "gif", "trim", "frames", "latest", "list",
        "get", "watch", "capture", "windows",
    ]
    /// The commands that answer that they're not on Linux yet.
    public static let notOnLinuxYetCommands = ["record", "pick"]
    /// The MCP tools that record or pick. Linux lists them, but they answer that they're not on Linux yet.
    public static let notOnLinuxYetTools = [AgentTools.recordWindow, AgentTools.askForCapture]

    public static func checks(_ facts: LinuxFacts) -> [Check] {
        [platform(facts), portal(facts), linuxAgents(facts), serve(facts), ffmpeg(facts), notOnLinuxYet, macOnly, emoji(facts), linuxFolder(facts)].compactMap { $0 }
    }

    static func platform(_ facts: LinuxFacts) -> Check {
        let detail = "Shot \(facts.version) on Linux, reading its settings from \(facts.settingsFile)."
        switch facts.sessionType?.lowercased() {
        case "x11": return Check("platform", .pass, detail + " The session is X11.")
        case "wayland": return Check("platform", .pass, detail + " The session is Wayland.")
        case let type:
            let session = type.map { "XDG_SESSION_TYPE is \($0)" } ?? "XDG_SESSION_TYPE isn't set"
            return Check("platform", .warn, detail + " \(session), so this isn't an X11 or Wayland session, which capturing will need.",
                         fix: "Run shot from a terminal in your desktop session.")
        }
    }

    /// Whether the desktop portal can take screenshots, which a Wayland session captures through; `nil` in any other.
    static func portal(_ facts: LinuxFacts) -> Check? {
        switch facts.screenshotPortal {
        case nil:
            return nil
        case let .success(version)?:
            return Check("screenshotPortal", .pass, "The desktop portal can take screenshots (Screenshot version \(version)), so shot serve captures screens and areas through it, and windows the user picks in the desktop's screenshot dialog.")
        case let .failure(error)?:
            return Check("screenshotPortal", .fail, error.message,
                         fix: "Install xdg-desktop-portal and your desktop's backend (\(ScreenshotPortal.backends)), and run shot from a terminal in your Wayland desktop session.")
        }
    }

    static func linuxAgents(_ facts: LinuxFacts) -> Check {
        guard facts.agentCapture else {
            return Check("letAgentsCaptureAndRecord", .warn, "Let agents capture and record is off, so shot capture, shot windows and the MCP tools that capture are refused. Reading captures works without it.",
                         fix: "Run shot settings agent-capture on, if agents should take their own screenshots.")
        }
        return Check("letAgentsCaptureAndRecord", .pass, "Let agents capture and record is on.")
    }

    /// Whether `shot serve` is running, which needn't be, since it starts when it's needed, and whether it can capture.
    static func serve(_ facts: LinuxFacts) -> Check {
        guard facts.listening else {
            return Check("serve", .pass, "shot serve isn't running. shot capture, shot windows and the MCP tools that capture start it when they need it.")
        }
        let stop = "Stop it with pkill -f \"shot serve\"; the next capture starts it again."
        let fields: [String: JSONValue]
        switch facts.status {
        case let .success(answer)?:
            fields = answer
        case let .failure(error)?:
            return Check("serve", .fail, "shot serve is listening at \(facts.socketPath) but didn't answer: \(error.message)", fix: stop)
        case nil:
            return Check("serve", .unknown, "shot serve is listening at \(facts.socketPath), but wasn't asked how it is.", fix: "Run shot doctor again.")
        }
        let running = fields["version"]?.string ?? "unknown"
        var check = Check("serve", .pass, "shot serve \(running) answers at \(facts.socketPath).")
        if case let .object(limits)? = fields["limits"], !limits.isEmpty {
            // A capturer that can't capture at all gives one reason for everything.
            var reasons: [String] = []
            for reason in limits.keys.sorted().compactMap({ limits[$0]?.string }) where !reasons.contains(reason) {
                reasons.append(reason)
            }
            check.detail += " " + reasons.joined(separator: " ")
        }
        if fields["capturer"]?.string == "none" {
            check.outcome = .warn
            // It picks its capturer when it starts, from the session it starts in.
            check.fix = facts.sessionType?.lowercased() == "wayland"
                ? "Fix what the screenshotPortal check says, then stop shot serve with pkill -f \"shot serve\"; the next capture starts it again."
                : "Stop shot serve with pkill -f \"shot serve\", then run a capture from a terminal in your X11 desktop session to start it there."
        }
        if running != facts.version {
            check.outcome = .warn
            check.detail += " This command is \(facts.version)."
            check.fix = stop
        }
        return check
    }

    /// Whether ffmpeg and ffprobe are installed, which video needs, and whether ffmpeg encodes H.264, which exporting an
    /// edited video needs, as trimming does when it can't copy the video, and HEVC, which only exports that ask for it need.
    static func ffmpeg(_ facts: LinuxFacts) -> Check? {
        guard let ffmpeg = facts.ffmpeg else {
            return nil
        }
        guard let program = ffmpeg.ffmpeg, let probe = ffmpeg.ffprobe else {
            let missing = [ffmpeg.ffmpeg == nil ? "ffmpeg" : nil, ffmpeg.ffprobe == nil ? "ffprobe" : nil].compactMap { $0 }.joined(separator: " or ")
            return Check("ffmpeg", .warn, "Shot reads, trims, joins and exports video with ffmpeg and ffprobe, and can't find \(missing).", fix: FFmpeg.install)
        }
        let detail = "\(ffmpeg.version.map { "ffmpeg \($0)" } ?? "ffmpeg") at \(program), with ffprobe at \(probe), reads, trims, joins and exports video."
        guard ffmpeg.encoders.contains(FFmpeg.h264Encoder) else {
            return Check("ffmpeg", .warn, detail + " It has no \(FFmpeg.h264Encoder), so it can't encode H.264, which exporting an edited video needs, as trimming does when it can't copy the video.",
                         fix: "Install an ffmpeg built with \(FFmpeg.h264Encoder), such as your distribution's ffmpeg package.")
        }
        guard ffmpeg.encoders.contains(FFmpeg.hevcEncoder) else {
            return Check("ffmpeg", .pass, detail + " It encodes H.264, and has no \(FFmpeg.hevcEncoder) for HEVC, which only exports that ask for it need.")
        }
        return Check("ffmpeg", .pass, detail + " It encodes H.264 and HEVC.")
    }

    static let notOnLinuxYet = Check(
        "notOnLinuxYet", .warn,
        "Recording and picking aren't on Linux yet: shot \(list(notOnLinuxYetCommands)) and the MCP tools \(list(notOnLinuxYetTools)) answer that they're not on Linux yet. The image and video commands and the tools that read and edit captures work, and shot capture, shot windows and the MCP tools that capture ask shot serve.",
        fix: "Use Shot on a Mac for those for now."
    )

    private static func list(_ names: [String]) -> String {
        names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }

    static let macOnly = Check(
        "macOnly", .pass,
        "Text recognition (find_text and shot text), redaction by text (redact --detect), the text index, narration and system audio need a Mac, so they're left out on Linux by design. Of image files, Linux opens PNG and JPEG, and makes GIFs; opening a GIF, HEIC, TIFF, BMP or WebP needs a Mac."
    )

    static func emoji(_ facts: LinuxFacts) -> Check {
        guard facts.colorEmoji else {
            return Check("emoji", .warn, "No colour emoji font is installed, so emoji in text and notes draw in black and white, or as empty boxes.",
                         fix: "Install one, such as Noto Color Emoji (fonts-noto-color-emoji on Debian and Ubuntu).")
        }
        return Check("emoji", .pass, "A colour emoji font is installed, so emoji in text and notes draw in colour.")
    }

    static func linuxFolder(_ facts: LinuxFacts) -> Check {
        guard facts.folderExists else {
            return Check("captureFolder", .warn, "\(facts.folder) doesn't exist yet, so there are no captures to read.",
                         fix: "Make the folder; captures are read from there.")
        }
        if let error = facts.folderError {
            return Check("captureFolder", .fail, "This user can't read \(facts.folder): \(error)", fix: "Check the folder's permissions.")
        }
        return Check("captureFolder", .pass, "\(facts.folder) can be read and holds \(facts.captures) \(facts.captures == 1 ? "capture" : "captures").")
    }
}
