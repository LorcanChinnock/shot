import Foundation
import Testing
@testable import ShotCoreLinux

@Test func everyToolButFindTextIsListedAndAnswersThatItsNotOnLinuxYet() async {
    let tools = AgentTools.live(folder: URL(fileURLWithPath: "/shots"))
    let names = tools.server(version: "1").tools.map(\.name)
    #expect(names == AgentTools.definitions.map(\.name).filter { $0 != AgentTools.findText })
    for name in names {
        let result = await tools.call(name, .object([:]))
        #expect(result == MCPServer.ToolResult(content: [.text("\(name): not on Linux yet")], isError: true))
    }
}

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
