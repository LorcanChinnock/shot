import Foundation
import os

private let log = Logger.shot("agent-cleanup")

/// What the removed agent features left on a Mac: their preferences, the `shot` link into the app, and the socket and
/// recording marks in the app's support folder. Run at every launch, since it does nothing once they're gone.
public enum LegacyAgentCleanup {
    static let keys = [
        "agentHandoff", "agentCapture", "sendToAgent", "sendToAgentPreset", "sendToAgentTerminal", "sendToAgentFolder",
        "sendToAgentCommand", "sendToAgentTemplate",
    ]
    /// The socket, the marks agents stamped on recordings, and the folder Send to Agent kept its copies in.
    static let files = ["agent.sock", "recording-marks.json", "Send to Agent"]

    /// Where the removed Settings › Agents page linked the command, as `shot` for a release and `shot-dev` for a dev build.
    static func linkPath(bundleID: String, folder: String = "/usr/local/bin") -> String {
        (folder as NSString).appendingPathComponent(bundleID == "dev.lorcan.Shot" ? "shot" : "shot-dev")
    }

    public static func run(bundleID: String, store: UserDefaults = .standard, support: URL? = nil, linkFolder: String = "/usr/local/bin") {
        for key in keys {
            store.removeObject(forKey: key)
        }
        let support = support ?? AppSupport.folder(bundleID: bundleID)
        for name in files {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }
        removeLink(at: linkPath(bundleID: bundleID, folder: linkFolder))
    }

    /// Removes the link only when it points at a `shot-cli` inside an app, so a `shot` the person installed themselves stays.
    static func removeLink(at path: String) {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path), target.hasSuffix("/Contents/MacOS/shot-cli") else {
            return
        }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            log.error("Couldn't remove the shot command at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
