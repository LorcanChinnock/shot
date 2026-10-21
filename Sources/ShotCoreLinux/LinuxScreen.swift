import Foundation

/// Picks the `ScreenCapturer` `shot serve` takes screenshots with, by the session `XDG_SESSION_TYPE` names: X11's, on
/// the X server `DISPLAY` names, or the desktop portal's on Wayland, over the session bus, with XWayland's X server for
/// X11 apps' windows. Without one, it answers why. On Wayland, the screen cast's restore token is kept in the `settings`
/// suite.
public enum LinuxScreen {
    public static func capturer(environment: [String: String] = ProcessInfo.processInfo.environment, settings: String? = nil) -> any ScreenCapturer {
        do {
            switch environment["XDG_SESSION_TYPE"]?.lowercased() {
            case "x11":
                return try X11Capturer(display: environment["DISPLAY"])
            case "wayland":
                guard let address = ScreenshotPortal.busAddress(environment: environment) else {
                    return NoCapturer(reason: ScreenshotPortal.noBus)
                }
                let xwayland = environment["DISPLAY"].flatMap { try? X11Capturer(display: $0) }
                return try PortalCapturer(address: address, xwayland: xwayland, settings: settings)
            case let session:
                return NoCapturer(session: session)
            }
        } catch {
            return NoCapturer(reason: error.message)
        }
    }

    /// The version of the portal's Screenshot interface, or why there's none, for `shot doctor` in a Wayland session;
    /// `nil` in any other.
    public static func screenshotPortal(environment: [String: String] = ProcessInfo.processInfo.environment) -> Result<Int, ShotCommandError>? {
        guard environment["XDG_SESSION_TYPE"]?.lowercased() == "wayland" else {
            return nil
        }
        guard let address = ScreenshotPortal.busAddress(environment: environment) else {
            return .failure(.unavailable(ScreenshotPortal.noBus))
        }
        return PortalCapturer.probe(address: address).map(Int.init)
    }

    /// The version of the portal's ScreenCast interface, or why there's none, with the version of libpipewire, which
    /// reads what it records, for `shot doctor` in a Wayland session; `nil` in any other.
    public static func screenCastPortal(environment: [String: String] = ProcessInfo.processInfo.environment) -> Doctor.ScreenCastFacts? {
        guard environment["XDG_SESSION_TYPE"]?.lowercased() == "wayland" else {
            return nil
        }
        let version: Result<Int, ShotCommandError>
        if let address = ScreenshotPortal.busAddress(environment: environment) {
            version = PortalCapturer.probeScreenCast(address: address).map { Int($0.version) }
        } else {
            version = .failure(.unavailable(ScreenshotPortal.noBus))
        }
        return Doctor.ScreenCastFacts(version: version, pipewire: PipeWireStream.libraryVersion)
    }
}

/// What `shot serve` has when nothing captures the session, or the session is neither X11 nor Wayland: it can do nothing, and each call answers why.
struct NoCapturer: ScreenCapturer {
    let reason: String

    init(reason: String) {
        self.reason = reason
    }

    init(session: String?) {
        reason = switch session {
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
