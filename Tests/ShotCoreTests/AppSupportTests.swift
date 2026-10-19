import Foundation
import Testing
@testable import ShotCore

@Test func appSupportFolderIsPerApp() {
    let folder = AppSupport.folder(bundleID: "dev.lorcan.Shot.test")
    #expect(folder.lastPathComponent == "dev.lorcan.Shot.test")
    #if canImport(Darwin)
    #expect(folder.deletingLastPathComponent().standardizedFileURL == URL.applicationSupportDirectory.standardizedFileURL)
    #endif
    #expect(AgentSocket.url(bundleID: "dev.lorcan.Shot.test") == folder.appendingPathComponent("agent.sock"))
    #expect(RecordingMarks.url(bundleID: "dev.lorcan.Shot.test") == folder.appendingPathComponent("recording-marks.json"))
}

#if os(Linux)
/// Runs in a process of its own, since changing the environment here would race every other test that reads it.
@Test func appSupportFolderFollowsXDGDataHome() async {
    await #expect(processExitsWith: .success) {
        unsetenv("XDG_DATA_HOME")
        // `$HOME`, as the XDG spec has it, which can differ from the user's home: a CI container sets it to /github/home.
        let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        guard AppSupport.folder(bundleID: "a").path == URL(fileURLWithPath: home).appendingPathComponent(".local/share/a").path else {
            exit(1)
        }
        setenv("XDG_DATA_HOME", "/tmp/xdg-data", 1)
        guard AppSupport.folder(bundleID: "a").path == "/tmp/xdg-data/a" else {
            exit(2)
        }
    }
}
#endif
