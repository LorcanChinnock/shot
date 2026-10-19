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
/// Changes the environment, so it's the only test that reads `XDG_DATA_HOME`.
@Test func appSupportFolderFollowsXDGDataHome() {
    let saved = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
    defer {
        if let saved {
            setenv("XDG_DATA_HOME", saved, 1)
        } else {
            unsetenv("XDG_DATA_HOME")
        }
    }
    unsetenv("XDG_DATA_HOME")
    // `$HOME`, as the XDG spec has it, which can differ from the user's home: a CI container sets it to /github/home.
    let home = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
    #expect(AppSupport.folder(bundleID: "a").path == URL(fileURLWithPath: home).appendingPathComponent(".local/share/a").path)
    setenv("XDG_DATA_HOME", "/tmp/xdg-data", 1)
    #expect(AppSupport.folder(bundleID: "a").path == "/tmp/xdg-data/a")
}
#endif
