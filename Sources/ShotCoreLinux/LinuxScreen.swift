import Foundation

/// Picks the `ScreenCapturer` `shot serve` takes screenshots with, by the session `XDG_SESSION_TYPE` names: X11's, on
/// the X server `DISPLAY` names, or the desktop portal's on Wayland once it comes (#749). Without one, it answers why.
public enum LinuxScreen {
    public static func capturer(environment: [String: String] = ProcessInfo.processInfo.environment) -> any ScreenCapturer {
        guard environment["XDG_SESSION_TYPE"]?.lowercased() == "x11" else {
            return NoCapturer(session: environment["XDG_SESSION_TYPE"])
        }
        do {
            return try X11Capturer(display: environment["DISPLAY"])
        } catch {
            return NoCapturer(reason: error.message)
        }
    }
}

/// What `shot serve` has when nothing captures the session: it can do nothing, and each call answers why.
struct NoCapturer: ScreenCapturer {
    let reason: String

    init(reason: String) {
        self.reason = reason
    }

    init(session: String?) {
        reason = switch session?.lowercased() {
        case "wayland": "Shot can't capture a Wayland session yet."
        case let session?: "XDG_SESSION_TYPE is \(session), and Shot can capture only an X11 or Wayland session."
        case nil: "XDG_SESSION_TYPE isn't set, so Shot can't tell which session to capture."
        }
    }

    var name: String { "none" }

    var limits: [ScreenCapability: String] {
        Dictionary(uniqueKeysWithValues: ScreenCapability.allCases.map { ($0, reason) })
    }

    func displays() async throws(ShotCommandError) -> [ScreenDisplay] { throw .unavailable(reason) }
    func windows() async throws(ShotCommandError) -> [ScreenWindow] { throw .unavailable(reason) }
    func capture(display: ScreenDisplay) async throws(ShotCommandError) -> Bitmap { throw .unavailable(reason) }
    func capture(window: ScreenWindow) async throws(ShotCommandError) -> Bitmap { throw .unavailable(reason) }
    func capture(area: CGRect) async throws(ShotCommandError) -> Bitmap { throw .unavailable(reason) }
}
