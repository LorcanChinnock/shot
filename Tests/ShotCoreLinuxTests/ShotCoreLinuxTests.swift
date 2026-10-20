import Foundation
import Testing
@testable import ShotCoreLinux

@Test func theSettingsAreTheReleasesInTheConfigHome() throws {
    #expect(LinuxSettings.suite == "dev.lorcan.Shot")
    #expect(LinuxSettings.file(suite: "dev.lorcan.Shot", environment: ["XDG_CONFIG_HOME": "/etc/me"]).path == "/etc/me/dev.lorcan.Shot.plist")
    let suite = "dev.lorcan.Shot.test-\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    let file = LinuxSettings.file(suite: suite)
    defer {
        store.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: file)
    }
    store.set("/data/shots", forKey: PreferenceKey.saveFolder)
    store.synchronize()
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test func capturesAreSavedToShotInThePicturesFolder() {
    let environment = ProcessInfo.processInfo.environment
    let pictures = XDG.picturesFolder(environment: environment, home: XDG.home(environment: environment))
    #expect(Preferences.defaultSaveFolder == pictures.appendingPathComponent("Shot").path)
}
