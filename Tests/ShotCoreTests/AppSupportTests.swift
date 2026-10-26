import Foundation
import Testing
@testable import ShotCore

@Test func appSupportFolderIsPerApp() {
    let folder = AppSupport.folder(bundleID: "dev.lorcan.Shot.test")
    #expect(folder.lastPathComponent == "dev.lorcan.Shot.test")
    #expect(folder.deletingLastPathComponent().standardizedFileURL == URL.applicationSupportDirectory.standardizedFileURL)
}
