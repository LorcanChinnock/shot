import Foundation
import ShotCore
import Testing

// The helpers of ShotCoreAppleTests' Fixtures.swift that need no Apple framework, for the tests that run on Linux too.

/// A new, empty folder in the temporary directory; the caller removes it.
func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// A preferences store of its own for one test; `remove()` deletes it and its file.
///
/// On macOS it lives in a temporary folder, not ~/Library/Preferences, because removing a domain there still leaves
/// cfprefsd to write an empty plist for it a moment later. Linux can't name a suite by a path: its Foundation reads a suite
/// through a this-user and an any-user domain, which a path makes the same file. Synchronizing any store writes out every
/// store, so the any-user domain can read a value this store then removes, and keep returning it (#777). So on Linux the
/// suite is a unique name, kept in `$XDG_CONFIG_HOME` like Shot's own settings.
struct TestDefaults {
    let name: String
    let store: UserDefaults
    private let file: URL

    init() throws {
        #if canImport(Darwin)
        let folder = try temporaryFolder()
        name = folder.appendingPathComponent("defaults").path
        file = folder
        #else
        name = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let environment = ProcessInfo.processInfo.environment
        file = XDG.configHome(environment: environment, home: XDG.home(environment: environment)).appendingPathComponent("\(name).plist")
        #endif
        store = try #require(UserDefaults(suiteName: name))
    }

    func remove() {
        store.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: file)
    }
}
