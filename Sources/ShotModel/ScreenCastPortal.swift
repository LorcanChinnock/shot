import Foundation

/// What `shot serve` decides without D-Bus when it records on Wayland through the desktop portal's ScreenCast
/// interface: what to ask for, what the answers mean, and how its errors read. A recording is a session, whose sources
/// the user picks in the desktop's dialog, or a restore token from an earlier one picks again without asking, and whose
/// frames come as a PipeWire stream.
public enum ScreenCastPortal {
    public static let interface = "org.freedesktop.portal.ScreenCast"
    /// The interface of the session object, which `Close` ends.
    public static let session = "org.freedesktop.portal.Session"
    /// The setting the restore token is kept in, so only the first recording of a screen shows the desktop's dialog.
    public static let tokenKey = "screenCastRestoreToken"

    /// `SelectSources`'s source types, as a bit mask.
    public static let monitor: UInt32 = 1, window: UInt32 = 2
    /// `cursor_mode`s, as a bit mask: left out, drawn into the frames, or sent beside them.
    public static let hiddenCursor: UInt32 = 1, embeddedCursor: UInt32 = 2, metadataCursor: UInt32 = 4
    /// The `persist_mode` that keeps the permission until it's revoked, so a token restores it after logging out too.
    public static let persistUntilRevoked: UInt32 = 2

    /// What the portal's ScreenCast interface can do, from its properties.
    public struct Properties: Equatable, Sendable {
        public var version: UInt32
        /// The source types it offers, as a bit mask of `monitor` and `window`.
        public var sourceTypes: UInt32
        /// The cursor modes it offers, as a bit mask.
        public var cursorModes: UInt32

        public init(version: UInt32, sourceTypes: UInt32 = ScreenCastPortal.monitor, cursorModes: UInt32 = 0) {
            self.version = version
            self.sourceTypes = sourceTypes
            self.cursorModes = cursorModes
        }
    }

    /// A stream `Start` answered with: its PipeWire node, and where its source is on the desktop and how big, in
    /// logical points, which a monitor at a scale of 2 sends twice as many pixels of.
    public struct Stream: Equatable, Sendable {
        public var node: UInt32
        public var position: CGPoint?
        public var size: CGSize?
        /// `monitor` or `window`, when it says.
        public var sourceType: UInt32?

        public init(node: UInt32, position: CGPoint? = nil, size: CGSize? = nil, sourceType: UInt32? = nil) {
            self.node = node
            self.position = position
            self.size = size
            self.sourceType = sourceType
        }
    }

    /// What `Start` answered with: the stream to read, and the token that picks the same source next time.
    public struct Started: Equatable, Sendable {
        public var stream: Stream
        public var restoreToken: String?

        public init(stream: Stream, restoreToken: String? = nil) {
            self.stream = stream
            self.restoreToken = restoreToken
        }
    }

    /// The `cursor_mode` that draws the pointer when `showsCursor`, or leaves it out, among the `available` modes:
    /// the other of the two when only it's there, and `nil`, asking for none, when neither is.
    public static func cursorMode(showsCursor: Bool, available: UInt32) -> UInt32? {
        let wanted = showsCursor ? embeddedCursor : hiddenCursor, other = showsCursor ? hiddenCursor : embeddedCursor
        if available & wanted != 0 {
            return wanted
        }
        return available & other != 0 ? other : nil
    }

    /// The source types to offer in the dialog: windows for a window, where the portal has them, or monitors.
    public static func sourceTypes(window: Bool, available: UInt32) -> UInt32 {
        window && available & Self.window != 0 ? Self.window : monitor
    }

    /// `SelectSources`'s options, but for the `handle_token` every request has: one source of `types`, with the pointer as `cursorMode`, if any. When it `persists`,
    /// the permission is kept until it's revoked, for a token to restore, and restored from `restoreToken` when there's
    /// one.
    public static func selectOptions(types: UInt32, cursorMode: UInt32?, persists: Bool, restoreToken: String?) -> [String: BusValue] {
        var options: [String: BusValue] = ["types": .uint32(types), "multiple": .bool(false)]
        if let cursorMode {
            options["cursor_mode"] = .uint32(cursorMode)
        }
        if persists {
            options["persist_mode"] = .uint32(persistUntilRevoked)
            if let restoreToken, !restoreToken.isEmpty {
                options["restore_token"] = .string(restoreToken)
            }
        }
        return options
    }

    /// The properties, from `GetAll`'s answer, or `nil` without a version, which every portal has.
    public static func properties(_ values: [String: BusValue]) -> Properties? {
        guard case let .uint32(version)? = values["version"] else {
            return nil
        }
        var properties = Properties(version: version)
        if case let .uint32(types)? = values["AvailableSourceTypes"] {
            properties.sourceTypes = types
        }
        if case let .uint32(modes)? = values["AvailableCursorModes"] {
            properties.cursorModes = modes
        }
        return properties
    }

    /// The session's object path from `CreateSession`'s results, which the spec gives as a string, and some portals as a
    /// path.
    public static func sessionHandle(response: UInt32, results: [String: BusValue]) throws(ShotCommandError) -> String {
        try check(response, step: "start a screen cast")
        switch results["session_handle"] {
        case let .string(handle)?, let .objectPath(handle)?:
            return handle
        default:
            throw .io("The desktop portal started a screen cast but didn't say which.")
        }
    }

    /// The first stream `Start` answered with, and the token to restore it with.
    public static func started(response: UInt32, results: [String: BusValue]) throws(ShotCommandError) -> Started {
        try check(response, step: "record the screen")
        guard case let .array(streams)? = results["streams"], case let .structure(fields)? = streams.first, fields.count == 2,
              case let .uint32(node) = fields[0]
        else {
            throw .io("The desktop portal started the screen cast but sent no stream to record.")
        }
        var stream = Stream(node: node)
        if case let .dictionary(properties) = fields[1] {
            stream.position = point(properties["position"])
            stream.size = point(properties["size"]).map { CGSize(width: $0.x, height: $0.y) }
            if case let .uint32(type)? = properties["source_type"] {
                stream.sourceType = type
            }
        }
        var token: String?
        if case let .string(text)? = results["restore_token"], !text.isEmpty {
            token = text
        }
        return Started(stream: stream, restoreToken: token)
    }

    /// An `(ii)` as a point.
    private static func point(_ value: BusValue?) -> CGPoint? {
        guard case let .structure(numbers)? = value, numbers.count == 2, case let .int32(x) = numbers[0], case let .int32(y) = numbers[1] else {
            return nil
        }
        return CGPoint(x: Double(x), y: Double(y))
    }

    /// Throws unless a request's `response` is `0`: `1` is the user cancelling or not allowing it, anything else the
    /// portal failing. `step` is what was being done, as in "couldn't record the screen".
    public static func check(_ response: UInt32, step: String) throws(ShotCommandError) {
        switch response {
        case 0:
            return
        case 1:
            throw .noInput("The recording was cancelled or not allowed in the desktop's dialog, so nothing was recorded.")
        default:
            throw .unavailable("The desktop portal couldn't \(step). Check that your desktop's portal backend (\(ScreenshotPortal.backends)) is installed.")
        }
    }

    /// Whether a D-Bus error from `SelectSources` is about the restore token, which a token that isn't valid any more
    /// gets, so it's forgotten and the user asked again.
    public static func isTokenProblem(name: String, message: String) -> Bool {
        name.hasSuffix(".InvalidArgument") && message.lowercased().contains("token")
    }

    /// A D-Bus error from calling the portal, in plain words, as `ScreenshotPortal.problem` reads the Screenshot
    /// interface's.
    public static func problem(name: String, message: String) -> ShotCommandError {
        switch name {
        case "org.freedesktop.DBus.Error.ServiceUnknown", "org.freedesktop.DBus.Error.NameHasNoOwner":
            .unavailable("The desktop portal isn't running, so Shot can't record on Wayland. Install xdg-desktop-portal and your desktop's backend: \(ScreenshotPortal.backends).")
        case "org.freedesktop.DBus.Error.UnknownInterface", "org.freedesktop.DBus.Error.UnknownMethod", "org.freedesktop.DBus.Error.UnknownObject",
             "org.freedesktop.DBus.Error.UnknownProperty", "org.freedesktop.DBus.Error.InvalidArgs":
            .unavailable(noBackend)
        case "org.freedesktop.DBus.Error.NoReply", "org.freedesktop.DBus.Error.Timeout", "org.freedesktop.DBus.Error.TimedOut":
            .unavailable("The desktop portal didn't answer in time. Try again; if it keeps happening, restart your desktop session.")
        case "org.freedesktop.portal.Error.NotAllowed", "org.freedesktop.DBus.Error.AccessDenied":
            .noPermission("The desktop portal didn't allow the recording: \(message)")
        default:
            .unavailable("The desktop portal couldn't record the screen: \(message.isEmpty ? name : message)")
        }
    }

    /// Why there's no recording where the portal has no ScreenCast backend.
    public static let noBackend = "The desktop portal is running but can't record the screen, since it has no ScreenCast backend. Install your desktop's: \(ScreenshotPortal.backends)."

    /// What a recording of a window the user picked in the desktop's dialog says, since it may not be the window asked
    /// for.
    public static let pickedNote = "Wayland doesn't let apps record a window by itself, so the user picked what to record in the desktop's dialog."

    /// The part of a stream's `frame`, `frame` pixels big, to record for `area`: in points on the desktop when
    /// `onDesktop`, where the stream's source is at its `position`, or in points from the source's top-left. Points are
    /// the frame's width over the source's logical width in pixels. The part is rounded out to whole pixels and down to
    /// an even width and height, which H.264's 4:2:0 needs, all of the frame, so evened, without an `area`, and `nil`
    /// when less than 2 × 2 pixels of it are on the frame.
    public static func crop(_ area: CGRect?, onDesktop: Bool, stream: Stream, frame: CGSize) -> CGRect? {
        var pixels = CGRect(origin: .zero, size: frame)
        if let area {
            let logical = stream.size.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil } ?? frame
            let scale = frame.width / logical.width
            let origin = onDesktop ? stream.position ?? .zero : .zero
            let points = area.offsetBy(dx: -origin.x, dy: -origin.y)
            pixels = CGRect(x: points.minX * scale, y: points.minY * scale, width: points.width * scale, height: points.height * scale)
        }
        // A hair of slack, so a scale like 1.25 doesn't round a whole frame out a pixel.
        let minX = (pixels.minX + 1e-6).rounded(.down), minY = (pixels.minY + 1e-6).rounded(.down)
        let maxX = (pixels.maxX - 1e-6).rounded(.up), maxY = (pixels.maxY - 1e-6).rounded(.up)
        guard maxX > minX, maxY > minY else {
            return nil
        }
        let onFrame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(CGRect(origin: .zero, size: frame))
        guard !onFrame.isNull else {
            return nil
        }
        let width = Int(onFrame.width) / 2 * 2, height = Int(onFrame.height) / 2 * 2
        guard width >= 2, height >= 2 else {
            return nil
        }
        return CGRect(x: onFrame.minX, y: onFrame.minY, width: Double(width), height: Double(height))
    }
}
