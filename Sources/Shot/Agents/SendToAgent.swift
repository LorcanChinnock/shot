import AppKit
import OSLog
import ShotCore

/// **Send to Agent**: opens the coding agent set up in Settings › Agents, in a terminal, with a capture and a prompt
/// built from its marks. Nothing runs until the user chooses it, and the agent runs on the user's own account.
@MainActor
enum SendToAgent {
    private static let log = Logger.shot("agents")

    /// Agents waiting, through `wait_for_capture`, for the person to send them a capture, oldest first. A send goes to
    /// the newest, and to it alone.
    private struct Waiter {
        let id: UUID
        let name: String
        let continuation: CheckedContinuation<AgentResponse, Never>
    }

    private static var waiters: [Waiter] = []

    /// Whether the menus show it: once it's turned on in Settings, as it's for people with a coding agent, or while an
    /// agent is waiting for a capture.
    static var isShown: Bool { Preferences().sendToAgent || !waiters.isEmpty }

    /// The menu item's title, naming the waiting agent, else the agent set up in Settings.
    static var title: String {
        if let waiting = waiters.last {
            return String(localized: "Send to \(waiting.name)")
        }
        return switch Preferences().sendToAgentPreset {
        case .claudeCode: String(localized: "Send to Claude Code")
        case .codex: String(localized: "Send to Codex")
        case .cursor: String(localized: "Send to Cursor")
        case .custom: String(localized: "Send to Agent")
        }
    }

    /// Waits up to `timeout` seconds for the person to send a capture, for an agent asking through the socket. Ends early
    /// when the agent hangs up, which cancels the task.
    static func wait(origin: ProjectOrigin?, timeout: Double) async -> AgentResponse {
        let id = UUID()
        let name = origin?.clientName ?? String(localized: "your agent")
        if waiters.isEmpty {
            Toast.show("\(name) is waiting for a capture. Choose Send to \(name) on one to send it.", duration: .seconds(4))
        }
        log.notice("An agent is waiting for a send")
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(id: id, name: name, continuation: continuation))
                Task {
                    try? await Task.sleep(for: .milliseconds(Int64(timeout * 1000)))
                    finish(id, with: .failure(.noInput("The user didn't send a capture within \(String(format: "%g", timeout)) seconds.")))
                }
            }
        } onCancel: {
            Task { @MainActor in finish(id, with: .failure(.noInput("The agent stopped waiting."))) }
        }
    }

    /// Answers the waiter `id`, if it's still waiting.
    private static func finish(_ id: UUID, with response: AgentResponse) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(returning: response)
    }

    /// Hands the image at `url` to the agent that's waiting for it, or else opens the agent set up in Settings in a
    /// terminal. `url` is the saved, flattened file, never an unmarked original, which would show what the user blurred.
    static func send(_ url: URL) async {
        let prefs = Preferences()
        guard ImageCodec.image(at: url) != nil else {
            Toast.error("Send to Agent sends screenshots. Couldn't read \(url.lastPathComponent) as an image.")
            return
        }
        if let waiting = waiters.last {
            let handoff = prefs.agentHandoff
            let sent = await Task.detached { () -> AgentSent in
                let record = handoff ? ImageCodec.record(ofFileAt: url) : nil
                let text = record == nil ? nil : try? await TextRecognizer.recognize(fileAt: url)
                // The agent asked through the MCP server, so it can call find_text.
                return AgentSent(path: url.path, prompt: AgentPrompt(path: url.path, record: record, text: text ?? nil, findText: true).string, record: record)
            }.value
            guard waiters.contains(where: { $0.id == waiting.id }) else {
                // It stopped waiting while the prompt was being built.
                Toast.error("\(waiting.name) stopped waiting. Send it again to open it in a terminal.")
                return
            }
            finish(waiting.id, with: .success(sent.fields))
            log.notice("Sent \(url.lastPathComponent, privacy: .private) to a waiting agent")
            Toast.show("Sent to \(waiting.name)")
            return
        }
        guard prefs.sendToAgent else {
            Toast.error("Turn on Send to Agent in Settings › Agents first.")
            return
        }
        let preset = prefs.sendToAgentPreset
        let terminal = prefs.sendToAgentTerminal
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) else {
            Toast.error("Couldn't find \(terminal.name). Choose another terminal in Settings › Agents.")
            return
        }
        var command = prefs.sendToAgentCommand
        // A path saved for another preset is looked up again, so Send to Codex never runs Claude Code.
        if let name = preset.command, !command.hasPrefix("/") || (command as NSString).lastPathComponent != name {
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
