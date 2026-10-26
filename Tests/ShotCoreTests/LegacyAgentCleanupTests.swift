import Foundation
import Testing
@testable import ShotCore

@Test func agentCleanupRemovesTheLeftoverPreferencesSocketAndMarks() throws {
    let suite = try TestDefaults()
    let store = suite.store
    defer { suite.remove() }
    for key in LegacyAgentCleanup.keys {
        store.set(true, forKey: key)
    }
    store.set("kept", forKey: "somethingElse")
    let support = FileManager.default.temporaryDirectory.appendingPathComponent("agent-cleanup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: support) }
    for name in LegacyAgentCleanup.files + ["text-index.json"] {
        try Data("x".utf8).write(to: support.appendingPathComponent(name))
    }

    LegacyAgentCleanup.run(bundleID: "dev.lorcan.Shot.tests", store: store, support: support, linkFolder: support.path)

    for key in LegacyAgentCleanup.keys {
        #expect(store.object(forKey: key) == nil)
    }
    #expect(store.string(forKey: "somethingElse") == "kept")
    for name in LegacyAgentCleanup.files {
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent(name).path))
    }
    #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("text-index.json").path))
}

@Test func agentCleanupRemovesTheShotLinkIntoAnAppButLeavesOthers() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-link-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let ours = LegacyAgentCleanup.linkPath(bundleID: "dev.lorcan.Shot", folder: folder.path)
    try FileManager.default.createSymbolicLink(atPath: ours, withDestinationPath: "/Applications/Shot.app/Contents/MacOS/shot-cli")
    LegacyAgentCleanup.removeLink(at: ours)
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: ours)) == nil)

    let theirs = LegacyAgentCleanup.linkPath(bundleID: "dev.lorcan.Shot.dev", folder: folder.path)
    try FileManager.default.createSymbolicLink(atPath: theirs, withDestinationPath: "/usr/local/bin/some-other-tool")
    LegacyAgentCleanup.removeLink(at: theirs)
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: theirs)) != nil)
}

@Test func agentCleanupLeavesTheLinkWhereItCantWriteTheFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-locked-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let link = LegacyAgentCleanup.linkPath(bundleID: "dev.lorcan.Shot", folder: folder.path)
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/Applications/Shot.app/Contents/MacOS/shot-cli")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }
    LegacyAgentCleanup.removeLink(at: link)
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != nil)
}
