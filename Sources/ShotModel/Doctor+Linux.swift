import Foundation

extension Doctor {
    /// What `shot doctor` checks on Linux, where there's no app yet to ask: the session, what runs so far, what's left
    /// out by design, the emoji font, and the capture folder.
    public struct LinuxFacts: Equatable, Sendable {
        public var version: String
        /// The settings file the command reads.
        public var settingsFile: String
        /// `XDG_SESSION_TYPE`, such as `x11` or `wayland`.
        public var sessionType: String?
        public var folder: String
        public var folderExists: Bool
        /// Why the folder couldn't be listed, or `nil` when it could.
        public var folderError: String?
        /// How many captures the folder holds, when it could be listed.
        public var captures: Int
        /// Whether a font that draws emoji in colour is installed.
        public var colorEmoji: Bool

        public init(
            version: String, settingsFile: String, sessionType: String?, folder: String, folderExists: Bool, folderError: String?, captures: Int,
            colorEmoji: Bool
        ) {
            self.version = version
            self.settingsFile = settingsFile
            self.sessionType = sessionType
            self.folder = folder
            self.folderExists = folderExists
            self.folderError = folderError
            self.captures = captures
            self.colorEmoji = colorEmoji
        }
    }

    /// The commands that run on Linux so far: the image commands and those that read the capture folder. `text`, and
    /// `redact --detect`, run only to say they need a Mac. The rest capture, record or read video, and answer
    /// `ShotCommandError.notOnLinuxYet`, as `info` and `edit` do on a video.
    public static let linuxCommands = ["version", "help", "doctor", "mcp", "info", "annotate", "redact", "crop", "diff", "edit", "latest", "list", "get", "watch"]
    /// The commands that answer that they're not on Linux yet.
    public static let notOnLinuxYetCommands = ["capture", "record", "windows", "pick", "gif", "trim", "frames"]
    /// The MCP tools that capture, record or read video. Linux lists them, but they answer that they're not on Linux yet.
    public static let notOnLinuxYetTools = [
        AgentTools.captureWindow, AgentTools.recordWindow, AgentTools.listWindows, AgentTools.askForCapture, AgentTools.getFrames, AgentTools.makeGIF,
        AgentTools.trimVideo, AgentTools.editVideo,
    ]

    public static func checks(_ facts: LinuxFacts) -> [Check] {
        [platform(facts), notOnLinuxYet, macOnly, emoji(facts), linuxFolder(facts)]
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

    static let notOnLinuxYet = Check(
        "notOnLinuxYet", .warn,
        "Capturing, recording and video aren't on Linux yet: shot \(list(notOnLinuxYetCommands)), info and edit on a video, and the MCP tools \(list(notOnLinuxYetTools)) answer that they're not on Linux yet. The image commands and the tools that read and edit screenshots work.",
        fix: "Use Shot on a Mac for those for now."
    )

    private static func list(_ names: [String]) -> String {
        names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }

    static let macOnly = Check(
        "macOnly", .pass,
        "Text recognition (find_text and shot text), redaction by text (redact --detect), the text index, narration and system audio need a Mac, so they're left out on Linux by design. Of image files, Linux opens PNG and JPEG; HEIC, TIFF, BMP and WebP need a Mac."
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
