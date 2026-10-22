import Foundation

/// The coding agents **Send to Agent** can open, each with how its command line takes the prompt and the image. Tested in
/// #493 for Claude Code; Codex and Cursor from their docs.
public enum AgentPreset: String, CaseIterable, Sendable {
    case claudeCode, codex, cursor, custom

    /// The command it runs, found on `PATH` when the preset is set up. `nil` for Custom, which names its own.
    public var command: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .cursor: "agent"
        case .custom: nil
        }
    }

    /// The arguments after the command, with `$shot_path`, `$shot_dir` and `$shot_prompt` set by the script. `--` ends
    /// the options, so a prompt that starts with `-` is still the prompt.
    /// - Claude Code can't read a file outside its working folder without `--add-dir`, which takes several folders and
    ///   would read the prompt as another (tested), so it's `--add-dir=`.
    /// - Codex's `-i` takes several values the same way, so it's `--image=`.
    /// - Cursor's `agent` reads the path from the prompt text.
    var arguments: String {
        switch self {
        case .claudeCode: #"--add-dir="$shot_dir" -- "$shot_prompt""#
        case .codex: #"--image="$shot_path" -- "$shot_prompt""#
        case .cursor: #"-- "$shot_prompt""#
        case .custom: #""$shot_prompt""#
        }
    }
}

/// The terminals Shot can open a script in. Each opens a `.command` file it's given, which needs no permission prompt,
/// where scripting it with AppleScript would ask to control it.
public enum AgentTerminal: String, CaseIterable, Sendable {
    case terminal, iTerm, ghostty, warp

    public var bundleID: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .warp: "dev.warp.Warp-Stable"
        }
    }

    public var name: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm: "iTerm"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        }
    }
}

/// The script **Send to Agent** writes and opens in a terminal: it starts in the working folder, runs the agent with the
/// prompt, then leaves a shell open there, since it's the user's session. Nothing is spliced into a command line: the
/// prompt comes from a quoted heredoc, which the shell reads as it is, and every path is single-quoted.
public struct AgentLaunch: Equatable, Sendable {
    public var preset: AgentPreset
    /// The agent's absolute path, found when the preset was set up, in case the terminal's shell doesn't read the
    /// user's `PATH`. For Custom, the user's template, with `{path}`, `{dir}` and `{prompt}`.
    public var command: String
    /// Where the agent starts, since it acts on the folder it starts in.
    public var folder: String
    /// The capture.
    public var path: String
    public var prompt: String

    public init(preset: AgentPreset, command: String, folder: String, path: String, prompt: String) {
        self.preset = preset
        self.command = command
        self.folder = folder
        self.path = path
        self.prompt = prompt
    }

    /// The custom template's placeholders, and the variables the script sets for them. zsh never splits or globs a
    /// variable, so these work bare or inside double quotes, as in `gemini -i "@{path} {prompt}"`.
    static let placeholders = ["{path}": "${shot_path}", "{dir}": "${shot_dir}", "{prompt}": "${shot_prompt}"]

    /// The line that runs the agent.
    var commandLine: String {
        guard preset == .custom else {
            return Self.quoted(command) + " " + preset.arguments
        }
        // A template without {prompt} still gets the prompt, at the end.
        let template = command.contains("{prompt}") ? command : command + " {prompt}"
        return Self.placeholders.reduce(template) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }

    public var script: String {
        let end = Self.terminator(for: prompt)
        var lines = [
            "#!/bin/zsh -l",
            "# Written by Shot for Send to Agent; it deletes itself once it starts.",
            #"rm -f -- "$0""#,
        ]
        // A login shell reads the user's profile, but not always their PATH for tools such as node, which an agent can
        // need: look beside the agent too.
        if preset != .custom, command.hasPrefix("/") {
            lines.append("export PATH=\(Self.quoted((command as NSString).deletingLastPathComponent)):\"$PATH\"")
        }
        lines += [
            "cd \(Self.quoted(folder)) || cd ~",
            "shot_path=\(Self.quoted(path))",
            "shot_dir=\(Self.quoted((path as NSString).deletingLastPathComponent))",
            "shot_prompt=$(cat <<'\(end)'",
            prompt,
            end,
            ")",
            commandLine,
            #"exec "${SHELL:-/bin/zsh}" -l"#,
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// `SHOT_EOF`, or that with a number when the prompt has a line that would end the heredoc early.
    static func terminator(for prompt: String) -> String {
        let lines = Set(prompt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        var end = "SHOT_EOF"
        var n = 1
        while lines.contains(end) {
            end = "SHOT_EOF_\(n)"
            n += 1
        }
        return end
    }

    /// `text` in single quotes, which the shell reads as it is, with any single quote closed, escaped and reopened.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Where the agent's command is likely to be when the app's own `PATH` doesn't have it: the install folders of
    /// Claude Code, npm, Homebrew and Cursor.
    public static func candidates(for command: String, home: String = NSHomeDirectory()) -> [String] {
        ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.cursor/bin", "\(home)/.bun/bin"]
            .map { "\($0)/\(command)" }
    }

    /// The agent's absolute path: from the user's login shell, which has their `PATH`, then the usual install folders.
    /// `nil` when it isn't installed.
    public static func locate(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "command -v -- \(quoted(command))"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        if (try? process.run()) != nil {
            process.waitUntilExit()
            let found = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) }
            if process.terminationStatus == 0, let found, found.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: found) {
                return found
            }
        }
        return candidates(for: command).first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
