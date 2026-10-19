import Foundation
import Testing
@testable import ShotModel

private let home = URL(fileURLWithPath: "/home/me", isDirectory: true)

@Test func homeIsHOMEWhenItsSetElseThePasswordDatabases() {
    #expect(XDG.home(environment: ["HOME": "/github/home"]).path == "/github/home")
    #expect(XDG.home(environment: [:]) == FileManager.default.homeDirectoryForCurrentUser)
}

@Test func theConfigHomeIsXDGConfigHomeWhenItsAnAbsolutePath() {
    #expect(XDG.configHome(environment: [:], home: home).path == "/home/me/.config")
    #expect(XDG.configHome(environment: ["XDG_CONFIG_HOME": "/etc/me"], home: home).path == "/etc/me")
    #expect(XDG.configHome(environment: ["XDG_CONFIG_HOME": "config"], home: home).path == "/home/me/.config")
}

@Test func aUserFolderIsReadAsXDGUserDirsUpdateWritesIt() {
    let contents = """
    # This file is written by xdg-user-dirs-update
    XDG_DESKTOP_DIR="$HOME/Desktop"
    XDG_PICTURES_DIR="$HOME/Bilder"
    XDG_VIDEOS_DIR="/data/videos"
    XDG_MUSIC_DIR=/data/music
    """
    #expect(XDG.userFolder("XDG_PICTURES_DIR", in: contents, home: home)?.path == "/home/me/Bilder")
    #expect(XDG.userFolder("XDG_VIDEOS_DIR", in: contents, home: home)?.path == "/data/videos")
    #expect(XDG.userFolder("XDG_MUSIC_DIR", in: contents, home: home)?.path == "/data/music")
    #expect(XDG.userFolder("XDG_DOWNLOAD_DIR", in: contents, home: home) == nil)
}

@Test func aUserFolderThatsHomeOrRelativeNamesNone() {
    #expect(XDG.userFolder("XDG_PICTURES_DIR", in: #"XDG_PICTURES_DIR="$HOME/""#, home: home) == nil)
    #expect(XDG.userFolder("XDG_PICTURES_DIR", in: #"XDG_PICTURES_DIR="$HOME""#, home: home) == nil)
    #expect(XDG.userFolder("XDG_PICTURES_DIR", in: #"XDG_PICTURES_DIR="Pictures""#, home: home) == nil)
    #expect(XDG.userFolder("XDG_PICTURES_DIR", in: #"# XDG_PICTURES_DIR="/data/pictures""#, home: home) == nil)
}

@Test func thePicturesFolderComesFromUserDirsInTheConfigHome() throws {
    let config = FileManager.default.temporaryDirectory.appendingPathComponent("XDGTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: config) }
    let environment = ["XDG_CONFIG_HOME": config.path]
    #expect(XDG.picturesFolder(environment: environment, home: home).path == "/home/me/Pictures")
    try Data(#"XDG_PICTURES_DIR="$HOME/Bilder""#.utf8).write(to: config.appendingPathComponent("user-dirs.dirs"))
    #expect(XDG.picturesFolder(environment: environment, home: home).path == "/home/me/Bilder")
}
