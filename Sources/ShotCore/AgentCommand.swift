import Foundation

/// Runs an agent's command line tool for Install in Settings › Agents, through the user's login shell, so it finds tools
/// on the PATH their terminal sets up, which an app opened from the Dock doesn't get.
public enum AgentCommand {
    public enum Outcome: Equatable, Sendable {
        case success
        case notFound
        /// Still running at the time limit, so it was stopped along with everything its shell started.
        case timedOut
        /// Stopped with `status`, after printing `message` as its last line, if anything.
        case failure(message: String?, status: Int32)
    }

    /// The user's shell when it's zsh or bash, whose `-i` and `-c` this relies on, else zsh.
    public static var shell: String {
        ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.hasSuffix("/zsh") || $0.hasSuffix("/bash") ? $0 : nil } ?? "/bin/zsh"
    }

    /// Runs `arguments`, the program's name then its arguments, through `shell`, waiting at most `timeout` seconds.
    /// `environment` replaces the app's own, for tests.
    public static func run(_ arguments: [String], shell: String = shell, environment: [String: String]? = nil, timeout: TimeInterval = 60) -> Outcome {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        // `-i` reads .zshrc or .bashrc too, where version managers like nvm add their tools. `$0` and `$@` keep each
        // argument whole, with no quoting.
        process.arguments = ["-l", "-i", "-c", #"exec "$0" "$@""#] + arguments
        if let environment {
            process.environment = environment
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return .failure(message: error.localizedDescription, status: -1)
        }
        // A shell setup that waits for input or hangs would otherwise hold the Install button forever. An interactive
        // shell ignores SIGTERM and carries on to run the command, and whatever it started keeps the output open, so
        // this kills its whole process group, which Process makes it the leader of.
        let pid = process.processIdentifier
        let limit = DispatchWorkItem { [process] in
            if process.isRunning {
                killpg(pid, SIGKILL)
            }
        }
        // A queue of its own, which gets a thread whatever else is running: on the shared global queue, the limit waits
        // behind any work blocked there, such as a socket read, and fires seconds late (#781).
        DispatchQueue(label: "dev.lorcan.Shot.agent-command-limit").asyncAfter(deadline: .now() + timeout, execute: limit)
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        limit.cancel()
        if process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGKILL {
            return .timedOut
        }
        switch process.terminationStatus {
        case 0:
            return .success
        case 127:
            return .notFound
        case let status:
            let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return .failure(message: lines.last, status: status)
        }
    }
}
