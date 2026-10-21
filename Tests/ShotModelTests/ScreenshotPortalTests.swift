import Foundation
import Testing
@testable import ShotModel

@Test func screenshotPortalFindsTheSessionBus() {
    #expect(ScreenshotPortal.busAddress(environment: ["DBUS_SESSION_BUS_ADDRESS": "unix:path=/tmp/bus", "XDG_RUNTIME_DIR": "/run/user/1000"]) == "unix:path=/tmp/bus")
    // Where systemd keeps it, as libdbus looks when the variable isn't set.
    #expect(ScreenshotPortal.busAddress(environment: ["XDG_RUNTIME_DIR": "/run/user/1000"]) { $0 == "/run/user/1000/bus" } == "unix:path=/run/user/1000/bus")
    #expect(ScreenshotPortal.busAddress(environment: ["XDG_RUNTIME_DIR": "/run/user/1000"]) { _ in false } == nil)
    #expect(ScreenshotPortal.busAddress(environment: ["DBUS_SESSION_BUS_ADDRESS": ""]) { _ in true } == nil)
}

@Test func screenshotPortalMakesHandleTokensItAccepts() {
    let token = ScreenshotPortal.token(3)
    #expect(token.hasPrefix("shot_3_"))
    #expect(token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
}

@Test func screenshotPortalReadsItsResponse() throws {
    #expect(try ScreenshotPortal.file(response: 0, uri: "file:///home/me/Pictures/Screenshot%20from%202026.png") == "/home/me/Pictures/Screenshot from 2026.png")
    #expect(ScreenshotPortal.path(uri: "https://example.com/a.png") == nil)
    #expect(throws: ShotCommandError.io("The desktop portal took the screenshot but didn't say where it saved it.")) {
        try ScreenshotPortal.file(response: 0, uri: nil)
    }
    #expect(throws: ShotCommandError.io("The desktop portal saved the screenshot at document:a.png, which isn't a local file.")) {
        try ScreenshotPortal.file(response: 0, uri: "document:a.png")
    }
    #expect(throws: ShotCommandError.noInput("The screenshot was cancelled or not allowed in the desktop's dialog, so nothing was captured.")) {
        try ScreenshotPortal.file(response: 1, uri: nil)
    }
    let failed = try #require(throws: ShotCommandError.self) { try ScreenshotPortal.file(response: 2, uri: nil) }
    #expect(failed.message.hasPrefix("The desktop portal couldn't take the screenshot."))
}

@Test func screenshotPortalSaysWhatWentWrongInPlainWords() {
    #expect(ScreenshotPortal.problem(name: "org.freedesktop.DBus.Error.ServiceUnknown", message: "The name is not activatable") == .unavailable(
        "The desktop portal isn't running, so Shot can't take screenshots on Wayland. Install xdg-desktop-portal and your desktop's backend: xdg-desktop-portal-gnome, xdg-desktop-portal-kde or xdg-desktop-portal-wlr."
    ))
    #expect(ScreenshotPortal.problem(name: "org.freedesktop.DBus.Error.InvalidArgs", message: "No such interface").message.hasPrefix(
        "The desktop portal is running but can't take screenshots, since it has no Screenshot backend."
    ))
    #expect(ScreenshotPortal.problem(name: "org.freedesktop.portal.Error.NotAllowed", message: "Screenshots are off") == .noPermission("The desktop portal didn't allow the screenshot: Screenshots are off"))
    #expect(ScreenshotPortal.problem(name: "org.example.Odd", message: "") == .unavailable("The desktop portal couldn't take the screenshot: org.example.Odd"))
}

@Test func screenshotPortalSaysWhichWindowsItLists() {
    #expect(ScreenshotPortal.windowsNote(xwayland: false) == "Wayland doesn't share its windows with apps, so none are listed. Capturing a window by name opens the desktop's screenshot dialog for the user to pick it.")
    #expect(ScreenshotPortal.windowsNote(xwayland: true).hasPrefix("Wayland doesn't share its windows with apps, so only X11 apps running through XWayland are listed."))
}
