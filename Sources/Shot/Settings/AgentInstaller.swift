import AppKit
import ShotCore

/// Adds Shot's MCP server to an agent when you click Install in Settings › Agents, the way `AgentClient.install` says:
/// by opening the agent's link, running its command line tool, or editing its config file.
@MainActor
enum AgentInstaller {
    /// Installs the server at `server` under `name` into `agent`, called `title` in messages, and reports how it went.
    /// `replacing` is for a server already set up under `name` that points elsewhere.
    static func install(_ agent: AgentClient, title: String, server: String, name: String, replacing: Bool) async {
        switch agent.install(server: server, name: name, replacing: replacing) {
        case let .link(link):
            guard let url = URL(string: link), NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                Toast.error("Couldn't open \(title). Copy the setup and add it there instead.")
                return
            }
            NSWorkspace.shared.open(url)
        case let .command(commands):
            let result = await Task.detached { () -> AgentCommand.Outcome in
                for arguments in commands {
                    if case let outcome = AgentCommand.run(arguments), outcome != .success {
                        return outcome
                    }
                }
                return .success
            }.value
            switch result {
            case .success:
                Toast.show("Added Shot to \(title).", duration: .seconds(3))
            case .notFound:
                Toast.error("Couldn't find the \(commands[0][0]) command. Copy the command and run it in Terminal instead.")
            case .timedOut:
                Toast.error("Couldn't add Shot to \(title): \(commands[0][0]) didn't finish within a minute. Copy the command and run it in Terminal instead.")
            case let .failure(message, status):
                Toast.error("Couldn't add Shot to \(title): \(message ?? String(localized: "it stopped with code \(status)."))")
            }
        case let .config(paths, key):
            let file = AgentClient.file(among: paths, home: NSHomeDirectory())
            if let failure = await Task.detached(operation: { write(server: server, name: name, key: key, to: file) }).value {
                Toast.error("Couldn't add Shot to \(title): \(failure)")
            } else {
                Toast.show("Added Shot to \(title). Restart \(title) to use it.", duration: .seconds(4))
            }
        case nil:
            break
        }
    }

    /// Adds the server to the JSON config at `file`, after copying it to a `.bak` beside it. Leaves a file that doesn't
    /// parse untouched. Returns why it couldn't, or nil once it has.
    private nonisolated static func write(server: String, name: String, key: String, to file: String) -> String? {
        let manager = FileManager.default
        let existing = manager.contents(atPath: file)
        let data: Data
        do {
            data = try AgentClient.adding(server: server, name: name, key: key, to: existing)
        } catch {
            return String(localized: "\((file as NSString).abbreviatingWithTildeInPath) isn't valid JSON, so Shot left it alone. Copy the setup and add it there instead.")
        }
        do {
            if existing != nil {
                let backup = file + ".bak"
                if manager.fileExists(atPath: backup) {
                    try manager.removeItem(atPath: backup)
                }
                try manager.copyItem(atPath: file, toPath: backup)
            }
            try manager.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: file), options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
