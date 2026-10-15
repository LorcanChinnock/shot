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
            let result = await Task.detached { () -> Outcome in
                for arguments in commands {
                    if case let outcome = run(arguments), outcome != .success {
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
            case let .failure(message):
                Toast.error("Couldn't add Shot to \(title): \(message)")
            }
        case let .config(path, key):
            let file = (NSHomeDirectory() as NSString).appendingPathComponent(path)
            if let failure = await Task.detached(operation: { write(server: server, name: name, key: key, to: file) }).value {
                Toast.error("Couldn't add Shot to \(title): \(failure)")
            } else {
                Toast.show("Added Shot to \(title). Restart \(title) to use it.", duration: .seconds(4))
            }
        case nil:
            break
        }
    }

    private enum Outcome: Equatable, Sendable {
        case success
        case notFound
        case failure(String)
    }

    /// Runs `arguments` through the user's login shell, so it finds tools on the PATH their terminal sets up, which an
    /// app opened from the Dock doesn't get.
    private nonisolated static func run(_ arguments: [String]) -> Outcome {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.hasSuffix("/zsh") || $0.hasSuffix("/bash") ? $0 : nil } ?? "/bin/zsh"
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        // `-i` reads .zshrc or .bashrc too, where version managers like nvm add their tools. `$0` and `$@` keep each
        // argument whole, with no quoting.
        process.arguments = ["-l", "-i", "-c", #"exec "$0" "$@""#] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return .failure(error.localizedDescription)
        }
        // A shell setup that waits for input would otherwise hold the Install button forever.
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) { [process] in
            if process.isRunning {
                process.terminate()
            }
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        switch process.terminationStatus {
        case 0:
            return .success
        case 127:
            return .notFound
        default:
            let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return .failure(lines.last ?? String(localized: "it stopped with code \(process.terminationStatus)."))
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
