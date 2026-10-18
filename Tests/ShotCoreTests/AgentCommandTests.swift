import Foundation
import Testing
@testable import ShotCore

/// Runs `arguments` through zsh with a startup file of `zshrc` in a folder of its own, so the tests never read the
/// user's own shell setup.
private func run(_ arguments: [String], zshrc: String = "", timeout: TimeInterval = 60) throws -> AgentCommand.Outcome {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-command-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try zshrc.write(to: folder.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
    var environment = ProcessInfo.processInfo.environment
    environment["ZDOTDIR"] = folder.path
    return AgentCommand.run(arguments, shell: "/bin/zsh", environment: environment, timeout: timeout)
}

@Test func agentCommandSucceedsWhenTheToolDoes() throws {
    #expect(try run(["true"]) == .success)
}

@Test func agentCommandReportsAToolThatIsntInstalled() throws {
    #expect(try run(["shot-no-such-command"]) == .notFound)
}

@Test func agentCommandReportsAFailureWithItsLastLine() throws {
    #expect(try run(["sh", "-c", "echo first; echo 'it broke'; exit 3"]) == .failure(message: "it broke", status: 3))
}

@Test func agentCommandFinishesWhenTheShellPrintsAndAsksOnStartup() throws {
    #expect(try run(["true"], zshrc: "echo Welcome\nprintf 'Update now? [Y/n] '\nread -r answer\n") == .success)
}

@Test func agentCommandStopsAShellThatHangsOnStartupWithoutRunningTheTool() throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("agent-command-ran-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    let start = Date()
    // Two slow steps: an interactive shell ignores SIGTERM, so stopping only the first would leave it running the second.
    #expect(try run(["touch", marker.path], zshrc: "sleep 30\nsleep 30\n", timeout: 1) == .timedOut)
    #expect(Date().timeIntervalSince(start) < 10)
    Thread.sleep(forTimeInterval: 1)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}
