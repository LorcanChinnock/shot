import Foundation
import Testing
@testable import ShotModel

/// A scratch folder with a fake app's `shot-cli`, a link folder and a Homebrew folder.
private struct Scratch {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    var cli: String { root + "/Shot.app/Contents/MacOS/shot-cli" }
    var folder: String { root + "/bin" }
    var brew: String { root + "/brew" }

    init() throws {
        for path in [(cli as NSString).deletingLastPathComponent, folder, brew] {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        try Data().write(to: URL(fileURLWithPath: cli))
    }

    func status() -> CommandLink.Status {
        CommandLink.status(name: "shot", cli: cli, folder: folder, homebrewFolder: brew)
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }
}

@Test func aReleaseInstallsShotAndADevBuildShotDev() {
    #expect(CommandLink.name(bundleID: "dev.lorcan.Shot") == "shot")
    #expect(CommandLink.name(bundleID: "dev.lorcan.Shot.dev") == "shot-dev")
    #expect(CommandLink.name(bundleID: nil) == "shot-dev")
}

@Test func theCommandIsMissingUntilItsLinked() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    #expect(scratch.status() == .missing)

    try FileManager.default.createSymbolicLink(atPath: scratch.folder + "/shot", withDestinationPath: scratch.cli)
    #expect(scratch.status() == .linked)
}

@Test func aRelativeLinkToThisAppCountsAsLinked() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    try FileManager.default.createSymbolicLink(atPath: scratch.folder + "/shot", withDestinationPath: "../Shot.app/Contents/MacOS/shot-cli")
    #expect(scratch.status() == .linked)
}

@Test func homebrewsLinkToThisAppNeedsNothingInstalled() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    try FileManager.default.createSymbolicLink(atPath: scratch.brew + "/shot", withDestinationPath: scratch.cli)
    #expect(scratch.status() == .homebrew)
}

@Test func aLinkToAMovedCopyOfShotIsStale() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let moved = scratch.root + "/Old/Shot.app/Contents/MacOS/shot-cli"
    try FileManager.default.createSymbolicLink(atPath: scratch.folder + "/shot", withDestinationPath: moved)
    #expect(scratch.status() == .stale(moved))
}

@Test func anotherProgramCalledShotIsLeftAlone() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let other = scratch.folder + "/shot"
    try Data().write(to: URL(fileURLWithPath: other))
    #expect(scratch.status() == .taken(other))
}

@Test func theInstallScriptQuotesPathsForTheShellAndAppleScript() {
    let script = CommandLink.installScript(name: "shot", cli: #"/Users/me/Apps/It's "Shot".app/Contents/MacOS/shot-cli"#, folder: "/usr/local/bin")
    #expect(script == #"do shell script "mkdir -p '/usr/local/bin' && ln -sfn '/Users/me/Apps/It'\\''s \"Shot\".app/Contents/MacOS/shot-cli' '/usr/local/bin/shot'" with administrator privileges"#)
}

@Test func theUninstallScriptRemovesOnlyTheLink() {
    #expect(CommandLink.uninstallScript(name: "shot-dev") == #"do shell script "rm -f '/usr/local/bin/shot-dev'" with administrator privileges"#)
}
