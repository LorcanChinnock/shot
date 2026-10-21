import Foundation
import Testing
@testable import ShotModel

@Test func x11ListsNormalWindowsOnScreenFrontToBack() {
    let back = X11Screen.Client(id: 1, stackIndex: 0, geometry: CGRect(x: 0, y: 0, width: 300, height: 200))
    let front = X11Screen.Client(id: 2, stackIndex: 3, geometry: CGRect(x: 10, y: 10, width: 100, height: 100))
    // Two clients in one frame keep the window manager's order.
    let tabA = X11Screen.Client(id: 3, stackIndex: 1, geometry: CGRect(x: 0, y: 0, width: 50, height: 50))
    let tabB = X11Screen.Client(id: 4, stackIndex: 1, geometry: CGRect(x: 0, y: 0, width: 50, height: 50))
    let left = [
        X11Screen.Client(id: 5, stackIndex: 2, viewable: false, geometry: CGRect(x: 0, y: 0, width: 100, height: 100)),
        X11Screen.Client(id: 6, stackIndex: 4, normal: false, geometry: CGRect(x: 0, y: 0, width: 100, height: 100)),
        X11Screen.Client(id: 7, stackIndex: 5, hidden: true, geometry: CGRect(x: 0, y: 0, width: 100, height: 100)),
        X11Screen.Client(id: 8, stackIndex: nil, geometry: CGRect(x: 0, y: 0, width: 100, height: 100)),
        X11Screen.Client(id: 9, stackIndex: 6, geometry: CGRect(x: 0, y: 0, width: 39, height: 100)),
        // 40 points tall only with its shadow.
        X11Screen.Client(id: 10, stackIndex: 7, geometry: CGRect(x: 0, y: 0, width: 100, height: 60), shadow: [10, 10, 10, 11]),
    ]
    #expect(X11Screen.listed([back, tabA, tabB, front] + left).map(\.id) == [2, 3, 4, 1])
}

@Test func x11CutsAWindowsOwnShadowFromItsFrame() {
    let window = X11Screen.Client(id: 1, stackIndex: 0, geometry: CGRect(x: 100, y: 50, width: 300, height: 200), shadow: [10, 20, 5, 15])
    #expect(window.content == CGRect(x: 110, y: 55, width: 270, height: 180))
    let plain = X11Screen.Client(id: 2, stackIndex: 0, geometry: CGRect(x: 1, y: 2, width: 3, height: 4), shadow: [1, 2])
    #expect(plain.content == plain.geometry)
}

@Test func x11PutsThePrimaryDisplayFirstAndShowsEachMirrorOnce() {
    let left = X11Screen.Output(name: "HDMI-1", crtc: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    let main = X11Screen.Output(name: "eDP-1", crtc: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1600), primary: true)
    let mirror = X11Screen.Output(name: "DP-2", crtc: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    let below = X11Screen.Output(name: "DP-1", crtc: 3, frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080))
    let off = X11Screen.Output(name: "DP-3", crtc: 4, frame: .zero)
    #expect(X11Screen.displays([below, left, off, main, mirror]).map(\.name) == ["eDP-1", "HDMI-1", "DP-1"])
    #expect(X11Screen.displays([below, left]).map(\.name) == ["HDMI-1", "DP-1"])
}

@Test func x11ReadsTheClassAndAnOldStyleTitle() {
    #expect(X11Screen.windowClass(Data("gnome-terminal-server\0Gnome-terminal\0".utf8)) == "Gnome-terminal")
    #expect(X11Screen.windowClass(Data("firefox".utf8)) == "")
    #expect(X11Screen.legacyText(Data("Café".utf8)) == "Café")
    #expect(X11Screen.legacyText(Data([0x43, 0x61, 0x66, 0xE9])) == "Café")
}

@Test func x11PixelsBecomeRGBAInEitherByteOrder() throws {
    // Two pixels a row and a padding byte pair, least significant byte first: blue, green, red, then alpha or unused.
    let little = Data([0x10, 0x20, 0x30, 0x00, 0x01, 0x02, 0x03, 0x80, 0xAA, 0xBB, 0x40, 0x50, 0x60, 0x00, 0x04, 0x05, 0x06, 0xFF])
    let opaque = try #require(Bitmap(x11: little, width: 2, height: 2, bytesPerRow: 10, mostSignificantFirst: false, alpha: false))
    #expect(opaque[0, 0] == (0x30, 0x20, 0x10, 255))
    #expect(opaque[1, 0] == (0x03, 0x02, 0x01, 255))
    #expect(opaque[1, 1] == (0x06, 0x05, 0x04, 255))
    let translucent = try #require(Bitmap(x11: little, width: 2, height: 2, bytesPerRow: 10, mostSignificantFirst: false, alpha: true))
    #expect(translucent[1, 0] == (0x03, 0x02, 0x01, 0x80))

    let big = try #require(Bitmap(x11: Data([0x80, 0x01, 0x02, 0x03]), width: 1, height: 1, bytesPerRow: 4, mostSignificantFirst: true, alpha: true))
    #expect(big[0, 0] == (0x01, 0x02, 0x03, 0x80))
    #expect(Bitmap(x11: little.prefix(16), width: 2, height: 2, bytesPerRow: 10, mostSignificantFirst: false, alpha: false) == nil)
}
