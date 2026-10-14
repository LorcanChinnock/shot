import Foundation

/// What `shot doctor` checks, from facts the command line gathers: which copy of Shot answers and its version, the
/// Screen Recording permission, Let agents capture and record, the socket, and the capture folder. Each check that
/// isn't passing says how to fix it. Here, with no file or socket access, so every outcome is tested on Linux.
public enum Doctor {
    public struct Facts: Equatable, Sendable {
        /// The app this command line is inside, or `nil` for a bare build reading `settingsSuite`.
        public var bundleID: String?
        public var appPath: String?
        public var version: String
        /// The settings read without an app around the command line.
        public var settingsSuite: String
        public var agentCapture: Bool
        public var socketPath: String
        /// Whether something accepts connections on the socket.
        public var listening: Bool
        /// The app's answer to a status request, or why it gave none, when it's listening.
        public var status: Result<[String: JSONValue], ShotCommandError>?
        public var folder: String
        public var folderExists: Bool
        /// Why the folder couldn't be listed, or `nil` when it could.
        public var folderError: String?
        /// How many captures the folder holds, when it could be listed.
        public var captures: Int

        public init(
            bundleID: String?, appPath: String?, version: String, settingsSuite: String, agentCapture: Bool, socketPath: String,
            listening: Bool, status: Result<[String: JSONValue], ShotCommandError>?, folder: String, folderExists: Bool,
            folderError: String?, captures: Int
        ) {
            self.bundleID = bundleID
            self.appPath = appPath
            self.version = version
            self.settingsSuite = settingsSuite
            self.agentCapture = agentCapture
            self.socketPath = socketPath
            self.listening = listening
            self.status = status
            self.folder = folder
            self.folderExists = folderExists
            self.folderError = folderError
            self.captures = captures
        }
    }

    public enum Outcome: String, Sendable {
        case pass
        /// Works, but something an agent may need is off.
        case warn
        case fail
        /// Couldn't be checked, because something before it failed.
        case unknown
    }

    public struct Check: Equatable, Sendable {
        public var name: String
        public var outcome: Outcome
        public var detail: String
        /// What to do about it, for anything but a pass.
        public var fix: String?

        public init(_ name: String, _ outcome: Outcome, _ detail: String, fix: String? = nil) {
            self.name = name
            self.outcome = outcome
            self.detail = detail
            self.fix = fix
        }
    }

    static let releaseID = "dev.lorcan.Shot"
    static let devID = "dev.lorcan.Shot.dev"

    /// Every check, in the order they depend on each other.
    public static func checks(_ facts: Facts) -> [Check] {
        [app(facts), agents(facts), socket(facts), permission(facts), folder(facts)]
    }

    /// The checks as `shot doctor` prints them: `ok` when none failed, then each check.
    public static func json(_ checks: [Check]) -> JSONValue {
        .object([
            "ok": .bool(!checks.contains { $0.outcome == .fail }),
            "checks": .array(checks.map { check in
                var object: [String: JSONValue] = ["name": .string(check.name), "outcome": .string(check.outcome.rawValue), "detail": .string(check.detail)]
                if let fix = check.fix {
                    object["fix"] = .string(fix)
                }
                return .object(object)
            }),
        ])
    }

    /// The copy's name as people know it: Shot for a release, ShotDev for a local build.
    static func name(_ bundleID: String) -> String {
        switch bundleID {
        case releaseID: "Shot"
        case devID: "ShotDev"
        default: bundleID
        }
    }

    static func app(_ facts: Facts) -> Check {
        guard let bundleID = facts.bundleID else {
            return Check("app", .warn, "This command isn't inside Shot.app, so it reads the \(facts.settingsSuite) settings and asks \(name(facts.settingsSuite)).",
                         fix: "Run the shot command that Settings › Agents installs, or Shot.app/Contents/MacOS/shot-cli.")
        }
        let place = facts.appPath.map { " at \($0)" } ?? ""
        var check = Check("app", .pass, "\(name(bundleID)) \(facts.version) (\(bundleID))\(place) answers this command.")
        if case let .success(fields)? = facts.status, let running = fields["version"]?.string, running != facts.version {
            check.outcome = .warn
            check.detail += " The copy that's running is \(running)."
            check.fix = "Quit \(name(bundleID)) and open it again, so the running copy matches this command."
        }
        return check
    }

    static func agents(_ facts: Facts) -> Check {
        guard facts.agentCapture else {
            return Check("letAgentsCaptureAndRecord", .warn, "Let agents capture and record is off, so shot capture, shot record and the MCP tools that capture are refused. Reading captures, shot pick and ask_for_capture work without it.",
                         fix: "Turn on Settings › Agents › Let agents capture and record in \(name(facts.bundleID ?? facts.settingsSuite)), if agents should take their own screenshots and recordings.")
        }
        return Check("letAgentsCaptureAndRecord", .pass, "Let agents capture and record is on.")
    }

    static func socket(_ facts: Facts) -> Check {
        let app = name(facts.bundleID ?? facts.settingsSuite)
        guard facts.agentCapture else {
            return Check("socket", .unknown, "Not checked, since Let agents capture and record is off.", fix: "Turn the setting on, then run shot doctor again.")
        }
        guard facts.listening else {
            return Check("socket", .fail, "Nothing answers at \(facts.socketPath).",
                         fix: "Open \(app); shot capture opens it in the background too. If it's open, turn Let agents capture and record off and on again.")
        }
        if case let .failure(error)? = facts.status {
            return Check("socket", .fail, "\(app) is listening at \(facts.socketPath) but didn't answer: \(error.message)",
                         fix: "Quit \(app) and open it again.")
        }
        return Check("socket", .pass, "\(app) answers at \(facts.socketPath).")
    }

    static func permission(_ facts: Facts) -> Check {
        let app = name(facts.bundleID ?? facts.settingsSuite)
        guard case let .success(fields)? = facts.status else {
            return Check("screenRecording", .unknown, "Only \(app) knows whether it has the permission, and it isn't answering.",
                         fix: facts.agentCapture ? "Fix the socket check above, then run shot doctor again." : "Turn on Let agents capture and record, then run shot doctor again.")
        }
        switch fields["screenRecording"] {
        case .bool(true)?:
            return Check("screenRecording", .pass, "\(app) has the Screen Recording permission.")
        case .bool(false)?:
            return Check("screenRecording", .fail, "\(app) doesn't have the Screen Recording permission, so it can't capture or record.",
                         fix: "Turn on \(app) in System Settings › Privacy & Security › Screen & System Audio Recording, then quit \(app) and open it again.")
        default:
            return Check("screenRecording", .unknown, "This copy of \(app) doesn't say whether it has the permission.",
                         fix: "Update \(app), so it matches this command.")
        }
    }

    static func folder(_ facts: Facts) -> Check {
        guard facts.folderExists else {
            return Check("captureFolder", .warn, "\(facts.folder) doesn't exist yet, so there are no captures to read.",
                         fix: "Take a screenshot with Shot, which makes the folder, or pick another save folder in Settings › General.")
        }
        if let error = facts.folderError {
            return Check("captureFolder", .fail, "macOS doesn't let this process read \(facts.folder): \(error)",
                         fix: "Allow the app running the agent, such as your terminal or editor, to access that folder in System Settings › Privacy & Security › Files and Folders, then start the agent again.")
        }
        return Check("captureFolder", .pass, "\(facts.folder) can be read and holds \(facts.captures) \(facts.captures == 1 ? "capture" : "captures").")
    }
}
