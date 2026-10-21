import Foundation

/// What `PortalCapturer` decides without D-Bus: where the session bus is, what the portal's answer means, and how its
/// errors read. On Wayland, apps take screenshots by asking the desktop portal's Screenshot interface, which saves the
/// picture to a file and answers with its URI, either at once or after the user picks a screen, window or area in the
/// desktop's own dialog.
public enum ScreenshotPortal {
    public static let service = "org.freedesktop.portal.Desktop"
    public static let object = "/org/freedesktop/portal/desktop"
    public static let interface = "org.freedesktop.portal.Screenshot"
    /// The interface of the object each request is answered on, with a `Response` signal.
    public static let request = "org.freedesktop.portal.Request"
    /// The desktops' backends, as Debian and Ubuntu package them.
    public static let backends = "xdg-desktop-portal-gnome, xdg-desktop-portal-kde or xdg-desktop-portal-wlr"

    /// The session bus's address: `DBUS_SESSION_BUS_ADDRESS`, or the socket systemd keeps in `XDG_RUNTIME_DIR`, as
    /// libdbus finds it when the variable isn't set.
    public static func busAddress(environment: [String: String], exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        if let address = environment["DBUS_SESSION_BUS_ADDRESS"], !address.isEmpty {
            return address
        }
        guard let runtime = environment["XDG_RUNTIME_DIR"], !runtime.isEmpty, exists(runtime + "/bus") else {
            return nil
        }
        return "unix:path=\(runtime)/bus"
    }

    /// Why there's no session bus to ask, when `busAddress` finds none.
    public static let noBus = "DBUS_SESSION_BUS_ADDRESS isn't set, so Shot can't find the session bus to ask the desktop portal for screenshots. Run shot from a terminal in your Wayland desktop session."

    /// A `handle_token`, which may hold only letters, digits and underscores.
    public static func token(_ number: Int) -> String {
        "shot_\(number)_\(UInt32.random(in: 0 ... .max))"
    }

    /// The file the portal saved the screenshot in, from the response's code and results: `0` is a screenshot, `1`
    /// the user cancelling or not allowing it, and anything else the portal failing.
    public static func file(response: UInt32, uri: String?) throws(ShotCommandError) -> String {
        switch response {
        case 0:
            guard let uri else {
                throw .io("The desktop portal took the screenshot but didn't say where it saved it.")
            }
            guard let path = path(uri: uri) else {
                throw .io("The desktop portal saved the screenshot at \(uri), which isn't a local file.")
            }
            return path
        case 1:
            throw .noInput("The screenshot was cancelled or not allowed in the desktop's dialog, so nothing was captured.")
        default:
            throw .unavailable("The desktop portal couldn't take the screenshot. Check that your desktop's portal backend (\(backends)) is installed.")
        }
    }

    /// The path a `file://` URI names, percent-decoded, or `nil` for anything else.
    public static func path(uri: String) -> String? {
        guard let url = URL(string: uri), url.isFileURL, !url.path.isEmpty else {
            return nil
        }
        return url.path
    }

    /// A D-Bus error from calling the portal, in plain words: `name` is the error's name, such as
    /// `org.freedesktop.DBus.Error.ServiceUnknown`, and `message` what came with it.
    public static func problem(name: String, message: String) -> ShotCommandError {
        switch name {
        case "org.freedesktop.DBus.Error.ServiceUnknown", "org.freedesktop.DBus.Error.NameHasNoOwner":
            .unavailable("The desktop portal isn't running, so Shot can't take screenshots on Wayland. Install xdg-desktop-portal and your desktop's backend: \(backends).")
        case "org.freedesktop.DBus.Error.UnknownInterface", "org.freedesktop.DBus.Error.UnknownMethod", "org.freedesktop.DBus.Error.UnknownObject",
             "org.freedesktop.DBus.Error.UnknownProperty", "org.freedesktop.DBus.Error.InvalidArgs":
            .unavailable("The desktop portal is running but can't take screenshots, since it has no Screenshot backend. Install your desktop's: \(backends).")
        case "org.freedesktop.DBus.Error.NoReply", "org.freedesktop.DBus.Error.Timeout", "org.freedesktop.DBus.Error.TimedOut":
            .unavailable("The desktop portal didn't answer in time. Try again; if it keeps happening, restart your desktop session.")
        case "org.freedesktop.portal.Error.NotAllowed", "org.freedesktop.DBus.Error.AccessDenied":
            .noPermission("The desktop portal didn't allow the screenshot: \(message)")
        default:
            .unavailable("The desktop portal couldn't take the screenshot: \(message.isEmpty ? name : message)")
        }
    }

    /// What `shot windows` and `list_windows` say about the windows they list on Wayland, which shares only X11 apps'
    /// windows, through XWayland, if any. `xwayland` is whether those are listed.
    public static func windowsNote(xwayland: Bool) -> String {
        let listed = xwayland
            ? "Wayland doesn't share its windows with apps, so only X11 apps running through XWayland are listed."
            : "Wayland doesn't share its windows with apps, so none are listed."
        return listed + " Capturing a window by name opens the desktop's screenshot dialog for the user to pick it."
    }

    /// What a capture the user picked in the desktop's dialog says, since it may not be the window asked for.
    public static let pickedNote = "Wayland doesn't let apps capture a window by itself, so the user picked what to capture in the desktop's screenshot dialog."
}
