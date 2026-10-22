import Foundation
import Testing
@testable import ShotCore

private let awkward = """
Fix the "Save" button's padding: it's $HOME `whoami` \\n wide.
SHOT_EOF
$(rm -rf ~)
"""

/// Runs `launch`'s script with a stand-in agent that writes its working folder and each argument on its own line.
private func run(_ launch: (String) -> AgentLaunch) throws -> [String] {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent launch \(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = folder.appendingPathComponent("args.txt")
    let agent = folder.appendingPathComponent("fake agent")
    try "#!/bin/sh\nprintf '%s\\n--\\n' \"$(pwd)\" > '\(output.path)'\nfor a in \"$@\"; do printf '%s\\n--\\n' \"$a\" >> '\(output.path)'; done\n"
        .write(to: agent, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: agent.path)
    let script = folder.appendingPathComponent("send.command")
    try launch(agent.path).script.write(to: script, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    // No login shell here, so the test doesn't read the profile of whoever runs it; the shell left open at the end
    // reads an empty stdin and exits.
    process.arguments = ["-f", script.path]
    process.currentDirectoryURL = folder
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.environment = ["SHELL": "/usr/bin/true", "PATH": "/usr/bin:/bin", "HOME": folder.path]
    try process.run()
    process.waitUntilExit()
    #expect(!FileManager.default.fileExists(atPath: script.path), "the script deletes itself")
    let text = try String(contentsOf: output, encoding: .utf8)
    return text.components(separatedBy: "\n--\n").map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.isEmpty }
}

private let capture = "/tmp/Shot 'quoted' folder/Shot 2026-10-22 at 09.14.03.png"

@Test func claudeCodeGetsTheCaptureFolderAndThePromptAsOneArgument() throws {
    let lines = try run { AgentLaunch(preset: .claudeCode, command: $0, folder: "/tmp", path: capture, prompt: awkward) }
    #expect(["/tmp", "/private/tmp"].contains(lines.first))
    #expect(Array(lines.dropFirst()) == ["--add-dir=/tmp/Shot 'quoted' folder", "--", awkward])
}

@Test func codexGetsTheImageWithAnEqualsSign() throws {
    let lines = try run { AgentLaunch(preset: .codex, command: $0, folder: "/tmp", path: capture, prompt: "hi") }
    #expect(Array(lines.dropFirst()) == ["--image=\(capture)", "--", "hi"])
}

@Test func cursorGetsOnlyThePrompt() throws {
    let lines = try run { AgentLaunch(preset: .cursor, command: $0, folder: "/tmp", path: capture, prompt: awkward) }
    #expect(Array(lines.dropFirst()) == ["--", awkward])
}

@Test func aPromptStartingWithADashIsStillThePrompt() {
    // Claude Code's --add-dir and Codex's --image take several values, so the prompt must never follow them bare.
    for preset in [AgentPreset.claudeCode, .codex, .cursor] {
        #expect(preset.arguments.hasSuffix(#"-- "$shot_prompt""#))
        #expect(!preset.arguments.contains(#"--add-dir ""#) && !preset.arguments.contains(#"--image ""#))
    }
}

@Test func aCustomTemplateFillsItsPlaceholdersInOrOutOfQuotes() throws {
    let lines = try run { agent in
        AgentLaunch(preset: .custom, command: AgentLaunch.quoted(agent) + #" -i "@{path} {prompt}" --dir {dir}"#, folder: "/tmp", path: capture, prompt: awkward)
    }
    #expect(Array(lines.dropFirst()) == ["-i", "@\(capture) \(awkward)", "--dir", "/tmp/Shot 'quoted' folder"])
}

@Test func aCustomTemplateWithoutThePromptGetsItAtTheEnd() {
    let launch = AgentLaunch(preset: .custom, command: "my-agent --file {path}", folder: "/", path: capture, prompt: "hi")
    #expect(launch.commandLine == "my-agent --file ${shot_path} ${shot_prompt}")
}

@Test(arguments: [
    "x\r\nSHOT_EOF\n)\ntouch pwned\n",
    "x\r\nSHOT_EOF\r\n)\r\ntouch pwned",
    "unbalanced ) and ( and `` and \\ and ' \" and \0 here",
    "SHOT_EOF\n)\ntouch pwned",
])
func noPromptRunsAsACommand(_ prompt: String) throws {
    let lines = try run { AgentLaunch(preset: .cursor, command: $0, folder: "/tmp", path: capture, prompt: prompt) }
    #expect(Array(lines.dropFirst()) == ["--", prompt.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .newlines)])
    #expect(!FileManager.default.fileExists(atPath: "/tmp/pwned"))
}

@Test func theHeredocEndsOnALineThePromptDoesntHave() {
    #expect(AgentLaunch.terminator(for: "hi") == "SHOT_EOF")
    #expect(AgentLaunch.terminator(for: "x\r\nSHOT_EOF\n") == "SHOT_EOF_1")
    #expect(AgentLaunch.terminator(for: "a\nSHOT_EOF\nSHOT_EOF_1") == "SHOT_EOF_2")
    #expect(AgentLaunch.terminator(for: "  SHOT_EOF") == "SHOT_EOF")
}

@Test func theScriptStartsInTheWorkingFolderAndKeepsTheShellOpen() {
    let script = AgentLaunch(preset: .claudeCode, command: "/Users/me/.local/bin/claude", folder: "/Users/me/My App", path: capture, prompt: "hi").script
    #expect(script.hasPrefix("#!/bin/zsh -l\n"))
    #expect(script.contains("export PATH='/Users/me/.local/bin':\"$PATH\"\n"))
    #expect(script.contains("cd '/Users/me/My App' || cd ~\n"))
    #expect(script.hasSuffix("exec \"${SHELL:-/bin/zsh}\" -l\n"))
}

@Test func candidatesCoverTheUsualInstallFolders() {
    let paths = AgentLaunch.candidates(for: "claude", home: "/Users/me")
    #expect(paths.first == "/Users/me/.local/bin/claude")
    #expect(paths.contains("/opt/homebrew/bin/claude"))
}
