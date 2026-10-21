import Foundation
import Testing
@testable import ShotCore

@Test func appSupportFolderIsPerApp() {
    let folder = AppSupport.folder(bundleID: "dev.lorcan.Shot.test")
    #expect(folder.lastPathComponent == "dev.lorcan.Shot.test")
    #expect(folder.deletingLastPathComponent().standardizedFileURL == URL.applicationSupportDirectory.standardizedFileURL)
    #expect(AgentSocket.url(bundleID: "dev.lorcan.Shot.test") == folder.appendingPathComponent("agent.sock"))
    #expect(RecordingMarks.url(bundleID: "dev.lorcan.Shot.test") == folder.appendingPathComponent("recording-marks.json"))
}
