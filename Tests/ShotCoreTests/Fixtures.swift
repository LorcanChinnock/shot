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
/// It lives in a temporary folder, not ~/Library/Preferences, because removing a domain there still leaves cfprefsd to
/// write an empty plist for it a moment later.
struct TestDefaults {
    let name: String
    let store: UserDefaults
    private let file: URL

    init() throws {
        let folder = try temporaryFolder()
        name = folder.appendingPathComponent("defaults").path
        file = folder
        store = try #require(UserDefaults(suiteName: name))
    }

    func remove() {
        store.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: file)
    }
}
