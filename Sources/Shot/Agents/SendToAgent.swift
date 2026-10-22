import AppKit
import OSLog
import ShotCore

/// **Send to Agent**: opens the coding agent set up in Settings › Agents, in a terminal, with a capture and a prompt
/// built from its marks. Nothing runs until the user chooses it, and the agent runs on the user's own account.
@MainActor
enum SendToAgent {
    private static let log = Logger.shot("agents")

    /// Whether the menus show it: only once it's turned on in Settings, as it's for people with a coding agent.
    static var isShown: Bool { Preferences().sendToAgent }

    /// The menu item's title, naming the agent.
    static var title: String {
        switch Preferences().sendToAgentPreset {
        case .claudeCode: String(localized: "Send to Claude Code")
        case .codex: String(localized: "Send to Codex")
        case .cursor: String(localized: "Send to Cursor")
        case .custom: String(localized: "Send to Agent")
        }
    }

    /// Writes the script that opens the agent with the image at `url` and opens it in the chosen terminal. `url` is the
    /// saved, flattened file, never an unmarked original, which would show what the user blurred.
    static func send(_ url: URL) async {
        let prefs = Preferences()
        // Also for `shot://send-to-agent`, so no other app can open a terminal while it's off.
        guard prefs.sendToAgent else {
            Toast.error("Turn on Send to Agent in Settings › Agents first.")
            return
        }
        guard ImageCodec.image(at: url) != nil else {
            Toast.error("Send to Agent sends screenshots. Couldn't read \(url.lastPathComponent) as an image.")
            return
        }
        let preset = prefs.sendToAgentPreset
        let terminal = prefs.sendToAgentTerminal
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) else {
            Toast.error("Couldn't find \(terminal.name). Choose another terminal in Settings › Agents.")
            return
        }
        var command = prefs.sendToAgentCommand
        if let name = preset.command, !command.hasPrefix("/") {
            guard let found = await Task.detached(operation: { AgentLaunch.locate(name) }).value else {
                Toast.error("Couldn't find the \(name) command. Install it, or choose another agent in Settings › Agents.")
                return
            }
            command = found
            UserDefaults.standard.set(found, forKey: PreferenceKey.sendToAgentCommand)
        }
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            MainWindowController.showSettings(section: .agents)
            Toast.error("Set the command for Send to Agent first.")
            return
        }
        let handoff = prefs.agentHandoff
        let client = AgentClient(preset)
        let server = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/shot-cli").path
        let name = CommandLink.name(bundleID: Bundle.main.bundleIdentifier)
        let prompt = await Task.detached { () -> String in
            // Without the record there are no marks to describe, so the text isn't read either.
            let record = handoff ? ImageCodec.record(ofFileAt: url) : nil
            let text = record == nil ? nil : try? await TextRecognizer.recognize(fileAt: url)
            let findText = client?.status(server: server, name: name, home: NSHomeDirectory()) == .installed
            return AgentPrompt(path: url.path, record: record, text: text ?? nil, findText: findText).string
        }.value
        let launch = AgentLaunch(preset: preset, command: command, folder: prefs.sendToAgentFolder, path: url.path, prompt: prompt)
        do {
            let script = try write(launch.script)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try await NSWorkspace.shared.open([script], withApplicationAt: app, configuration: configuration)
            log.notice("Sent \(url.lastPathComponent, privacy: .private) to \(preset.rawValue) in \(terminal.rawValue)")
        } catch {
            log.error("Send to Agent failed: \(error.localizedDescription)")
            Toast.error("Couldn't open \(terminal.name): \(error.localizedDescription)")
        }
    }

    /// The script, owner-only, in Application Support. It deletes itself once it starts; any left from a terminal that
    /// never ran one are cleared after a day.
    private static func write(_ script: String) throws -> URL {
        let folder = AppSupport.folder(bundleID: Bundle.main.bundleIdentifier ?? "dev.lorcan.Shot").appendingPathComponent("Send to Agent", isDirectory: true)
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let old = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in old {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < Date(timeIntervalSinceNow: -86400) {
                try? files.removeItem(at: file)
            }
        }
        let url = folder.appendingPathComponent("send-\(UUID().uuidString.prefix(8)).command")
        guard files.createFile(atPath: url.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o700]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }
}

private extension AgentClient {
    /// The MCP client a preset's agent reads its servers from, to tell whether it can call `find_text`.
    init?(_ preset: AgentPreset) {
        switch preset {
        case .claudeCode: self = .claudeCode
        case .codex: self = .codex
        case .cursor: self = .cursor
        case .custom: return nil
        }
    }
}
