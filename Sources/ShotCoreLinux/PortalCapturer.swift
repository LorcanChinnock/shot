import Foundation
import Synchronization

/// Captures a Wayland session through the desktop portal's Screenshot interface, which GNOME, KDE and wlroots desktops
/// answer through their xdg-desktop-portal backend. Wayland doesn't let apps list or capture windows, so a screen is
/// captured without asking, which the portal allows apps outside a sandbox, and a window by name becomes the desktop's
/// own screenshot dialog, where the user picks it. X11 apps running through XWayland can still be listed and captured
/// silently, through `X11Capturer`.
///
/// The portal gives one picture of every screen together, so that's the one display, and it doesn't say the scale, so a
/// point is one of its pixels. It saves the picture to a file and answers with its URI; that file is read and deleted, so
/// `shot serve` saves it in the capture folder instead. It records through the ScreenCast interface, as
/// `ScreenCastRecording` does. libdbus does the talking, without a main loop, on a queue of its own, since a call blocks
/// until the portal answers.
final class PortalCapturer: ScreenCapturer, @unchecked Sendable {
    // Used only on `queue`.
    private let bus: SessionBus
    private let queue = DispatchQueue(label: "dev.lorcan.Shot.portal")
    private var requests = 0
    private let xwayland: X11Capturer?
    private let codec = PNGJPEGCodec()
    /// The size of the last screenshot, which `displays()` gives rather than taking one each time, and the screenshot
    /// itself while it's fresh, for the capture that follows.
    private let last = Mutex<(size: CGSize, fresh: (image: Bitmap, taken: ContinuousClock.Instant)?)?>(nil)
    /// The version of the portal's Screenshot interface.
    let version: UInt32
    /// What the portal's ScreenCast interface can do, or why there's none, which recording needs.
    let screenCast: Result<ScreenCastPortal.Properties, ShotCommandError>
    /// The settings suite the screen cast's restore token is kept in, or `nil` to keep none.
    private let settings: String?

    /// How long the portal has to answer a screenshot nobody's asked about.
    static let answerTime = Duration.seconds(30)
    /// How long the user has to pick something in the desktop's dialog, as long as `shot pick` waits.
    static let pickTime = Duration.seconds(ShotCommand.PickOptions.defaultTimeout)
    /// How long a screenshot `displays()` took stays fresh enough for the capture after it.
    static let freshTime = Duration.seconds(2)

    /// Connects to the session bus at `address` and checks the portal can take screenshots, and whether it can record.
    /// `xwayland` lists and captures X11 apps' windows, and the screen cast's restore token is kept in the `settings`
    /// suite.
    init(address: String, xwayland: X11Capturer? = nil, settings: String? = nil) throws(ShotCommandError) {
        bus = try SessionBus(address: address)
        version = try Self.screenshotVersion(on: bus)
        screenCast = Self.screenCastProperties(on: bus)
        self.xwayland = xwayland
        self.settings = settings
    }

    /// The version of the Screenshot interface the portal on the bus at `address` has, or why there's none.
    static func probe(address: String) -> Result<UInt32, ShotCommandError> {
        Result { () throws(ShotCommandError) in try screenshotVersion(on: try SessionBus(address: address)) }
    }

    /// What the ScreenCast interface of the portal on the bus at `address` can do, or why there's none.
    static func probeScreenCast(address: String) -> Result<ScreenCastPortal.Properties, ShotCommandError> {
        Result { () throws(ShotCommandError) in try SessionBus(address: address) }.flatMap(screenCastProperties)
    }

    private static func screenCastProperties(on bus: SessionBus) -> Result<ScreenCastPortal.Properties, ShotCommandError> {
        let get = BusMessage.call(
            destination: ScreenshotPortal.service, path: ScreenshotPortal.object, interface: "org.freedesktop.DBus.Properties", member: "GetAll",
            [.string(ScreenCastPortal.interface)]
        )
        let reply: BusMessage
        do {
            reply = try bus.call(get, timeout: .seconds(10))
        } catch {
            return .failure(ScreenCastPortal.problem(name: error.name, message: error.message))
        }
        // A portal without a ScreenCast backend may answer with no properties rather than an error.
        guard case let .dictionary(values)? = reply.arguments.first, let properties = ScreenCastPortal.properties(values) else {
            return .failure(.unavailable(ScreenCastPortal.noBackend))
        }
        return .success(properties)
    }

    private static func screenshotVersion(on bus: SessionBus) throws(ShotCommandError) -> UInt32 {
        let get = BusMessage.call(
            destination: ScreenshotPortal.service, path: ScreenshotPortal.object, interface: "org.freedesktop.DBus.Properties", member: "Get",
            [.string(ScreenshotPortal.interface), .string("version")]
        )
        let reply: BusMessage
        do {
            reply = try bus.call(get, timeout: .seconds(10))
        } catch {
            throw ScreenshotPortal.problem(name: error.name, message: error.message)
        }
        guard case let .variant(.uint32(version))? = reply.arguments.first else {
            throw .unavailable("The desktop portal answered with something Shot doesn't understand when asked about screenshots.")
        }
        return version
    }

    var name: String { "portal" }
    var limits: [ScreenCapability: String] {
        guard case let .failure(error) = screenCast else {
            return [:]
        }
        return [.record: error.message]
    }
    var windowsNote: String? { ScreenshotPortal.windowsNote(xwayland: xwayland != nil) }

    func displays() async throws(ShotCommandError) -> [ScreenDisplay] {
        var size = last.withLock { $0?.size }
        if size == nil {
            let image = try await screenshot(interactive: false)
            last.withLock { $0?.fresh = (image, .now) }
            size = CGSize(width: image.width, height: image.height)
        }
        return [ScreenDisplay(name: "screen", frame: CGRect(origin: .zero, size: size ?? .zero))]
    }

    func windows() async throws(ShotCommandError) -> [ScreenWindow] {
        try await xwayland?.windows() ?? []
    }

    func capture(display: ScreenDisplay) async throws(ShotCommandError) -> Bitmap {
        try await freshScreenshot()
    }

    func capture(window: ScreenWindow) async throws(ShotCommandError) -> Bitmap {
        guard let xwayland else {
            throw .unavailable(ScreenshotPortal.pickedNote)
        }
        return try await xwayland.capture(window: window)
    }

    func capture(area: CGRect) async throws(ShotCommandError) -> Bitmap {
        let image = try await freshScreenshot()
        let shown = area.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !shown.isNull, shown.width >= 1, shown.height >= 1, let cropped = image.cropped(to: shown) else {
            throw .data("The area at \(Int(area.minX)),\(Int(area.minY)), \(Int(area.width))×\(Int(area.height)) points, is off the screen.")
        }
        return cropped
    }

    func capturePicked() async throws(ShotCommandError) -> Bitmap? {
        try await screenshot(interactive: true)
    }

    /// Records the screen a stored restore token picks, or the user picks in the desktop's dialog, which is the one
    /// display `displays()` gives, or `area` of it, in points of the whole desktop. All of the display is all of the
    /// screen, since the screenshot that sized it may count the points otherwise.
    func recordingSource(area: CGRect, frameRate: Int, showsCursor: Bool) throws(ShotCommandError) -> any RecordingSource {
        _ = try screenCast.get()
        let whole = last.withLock { $0?.size }.map { area == CGRect(origin: .zero, size: $0) } ?? false
        return ScreenCastRecording(portal: self, window: false, area: whole ? nil : area, frameRate: frameRate, showsCursor: showsCursor)
    }

    /// Records the window the user picks in the desktop's dialog, or a screen, where the portal offers no windows, which
    /// Wayland never lets an app pick by itself.
    func pickedRecordingSource(rect: CGRect?, frameRate: Int, showsCursor: Bool) throws(ShotCommandError) -> (any RecordingSource)? {
        _ = try screenCast.get()
        return ScreenCastRecording(portal: self, window: true, area: rect, frameRate: frameRate, showsCursor: showsCursor)
    }

    /// The screenshot `displays()` just took, if it's fresh, or a new one.
    private func freshScreenshot() async throws(ShotCommandError) -> Bitmap {
        let kept = last.withLock { state -> Bitmap? in
            defer { state?.fresh = nil }
            guard let fresh = state?.fresh, ContinuousClock.now - fresh.taken < Self.freshTime else {
                return nil
            }
            return fresh.image
        }
        if let kept {
            return kept
        }
        return try await screenshot(interactive: false)
    }

    /// Asks the portal for a screenshot of every screen, or of what the user picks in the desktop's dialog.
    private func screenshot(interactive: Bool) async throws(ShotCommandError) -> Bitmap {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Bitmap, ShotCommandError>, Never>) in
            queue.async {
                continuation.resume(returning: Result { () throws(ShotCommandError) in try self.takeScreenshot(interactive: interactive) })
            }
        }
        let image = try result.get()
        if !interactive {
            last.withLock { $0 = (CGSize(width: image.width, height: image.height), nil) }
        }
        return image
    }

    /// Calls the portal's `Screenshot` and waits for its answer. On `queue`.
    private func takeScreenshot(interactive: Bool) throws(ShotCommandError) -> Bitmap {
        let wait = interactive ? Self.pickTime : Self.answerTime
        let answer: (response: UInt32, results: [String: BusValue])?
        do {
            answer = try request(
                ScreenshotPortal.interface, "Screenshot", [.string("")], options: ["interactive": .bool(interactive), "modal": .bool(true)], wait: wait
            )
        } catch {
            throw ScreenshotPortal.problem(name: error.name, message: error.message)
        }
        guard let answer else {
            throw interactive
                ? .noInput("Nothing was picked in the desktop's screenshot dialog within \(wait.components.seconds) seconds, so nothing was captured.")
                : .unavailable("The desktop portal didn't take the screenshot within \(wait.components.seconds) seconds.")
        }
        var uri: String?
        if case let .string(text)? = answer.results["uri"] {
            uri = text
        }
        let path = try ScreenshotPortal.file(response: answer.response, uri: uri)
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard let image = codec.decode(fileAt: URL(fileURLWithPath: path)) else {
            throw .data("Shot couldn't read the screenshot the desktop portal saved at \(path).")
        }
        return image
    }

    /// Calls `member` of `interface` with `arguments` and then `options`, with a `handle_token` added, and waits up to
    /// `wait` for the `Response` on the request object it names, listening before the call so the answer can't come
    /// first. Gives the response's code and results, a code of 2 for one it can't read, or `nil` when none came in time,
    /// having closed the request, so a dialog doesn't wait for the user after the agent has given up. Throws the call's
    /// D-Bus error. On `queue`.
    private func request(
        _ interface: String, _ member: String, _ arguments: [BusValue], options: [String: BusValue], wait: Duration
    ) throws(BusError) -> (response: UInt32, results: [String: BusValue])? {
        requests += 1
        var options = options
        options["handle_token"] = .string(ScreenshotPortal.token(requests))
        // Every response, rather than the one on the path the token gives, since portals before version 0.9 of the
        // spec make up their own path, which comes only with the reply.
        let rule = "type='signal',interface='\(ScreenshotPortal.request)',member='Response'"
        try bus.addMatch(rule)
        defer { bus.removeMatch(rule) }
        let call = BusMessage.call(destination: ScreenshotPortal.service, path: ScreenshotPortal.object, interface: interface, member: member, arguments + [.dictionary(options)])
        let reply = try bus.call(call, timeout: .seconds(10))
        guard case let .objectPath(handle)? = reply.arguments.first else {
            throw BusError(name: "", message: "The desktop portal answered with something Shot doesn't understand.")
        }
        let deadline = ContinuousClock.now + wait
        while let message = bus.next(until: deadline) {
            guard message.isSignal(ScreenshotPortal.request, "Response"), message.path == handle else {
                continue
            }
            let arguments = message.arguments
            guard case let .uint32(response)? = arguments.first else {
                return (2, [:])
            }
            guard arguments.count > 1, case let .dictionary(results) = arguments[1] else {
                return (response, [:])
            }
            return (response, results)
        }
        bus.send(BusMessage.call(destination: ScreenshotPortal.service, path: handle, interface: ScreenshotPortal.request, member: "Close"))
        return nil
    }

    // MARK: Screen casts

    /// A screen cast the portal has started: its session, the stream it sends, and a PipeWire connection that can see it.
    struct ScreenCast: Sendable {
        let session: String
        let started: ScreenCastPortal.Started
        /// The connection's file descriptor, which whoever reads the stream takes.
        let fd: Int32
    }

    /// Starts a screen cast of a window the user picks, or a screen, which the restore token kept from the last one picks
    /// again without asking, with the pointer drawn when `showsCursor`.
    func screenCast(window: Bool, showsCursor: Bool) async throws(ShotCommandError) -> ScreenCast {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<ScreenCast, ShotCommandError>, Never>) in
            queue.async {
                continuation.resume(returning: Result { () throws(ShotCommandError) in try self.startScreenCast(window: window, showsCursor: showsCursor) })
            }
        }
        return try result.get()
    }

    /// Ends a screen cast, which takes down its stream.
    func close(_ cast: ScreenCast) {
        queue.async { [bus] in
            bus.send(BusMessage.call(destination: ScreenshotPortal.service, path: cast.session, interface: ScreenCastPortal.session, member: "Close"))
        }
    }

    /// The restore token kept from the last screen cast of a screen.
    private var restoreToken: String? {
        get { settings.flatMap { UserDefaults(suiteName: $0)?.string(forKey: ScreenCastPortal.tokenKey) } }
        set {
            guard let settings, let store = UserDefaults(suiteName: settings) else {
                return
            }
            store.set(newValue, forKey: ScreenCastPortal.tokenKey)
            store.synchronize()
        }
    }

    /// Why a screen cast couldn't start: its restore token was turned down, or anything else.
    private enum CastFailure: Error {
        case tokenRejected
        case failed(ShotCommandError)
    }

    /// Starts a screen cast, asking again without the restore token when the portal turns it down, and keeps the token
    /// it gives for a screen. On `queue`.
    private func startScreenCast(window: Bool, showsCursor: Bool) throws(ShotCommandError) -> ScreenCast {
        let properties = try screenCast.get()
        let token = window ? nil : restoreToken
        let cast: ScreenCast
        do {
            cast = try startScreenCast(window: window, showsCursor: showsCursor, properties: properties, token: token)
        } catch let .failed(error) {
            throw error
        } catch {
            // The portal turned the token down, so the user is asked again.
            restoreToken = nil
            do {
                cast = try startScreenCast(window: window, showsCursor: showsCursor, properties: properties, token: nil)
            } catch let .failed(error) {
                throw error
            } catch {
                throw .unavailable("The desktop portal turned down the screen cast.")
            }
        }
        if !window, let token = cast.started.restoreToken {
            restoreToken = token
        }
        return cast
    }

    /// `CreateSession`, `SelectSources`, `Start` and `OpenPipeWireRemote`, closing the session if a step fails. On
    /// `queue`.
    private func startScreenCast(window: Bool, showsCursor: Bool, properties: ScreenCastPortal.Properties, token: String?) throws(CastFailure) -> ScreenCast {
        let fail = { (error: BusError) in CastFailure.failed(ScreenCastPortal.problem(name: error.name, message: error.message)) }
        let late = CastFailure.failed(.unavailable("The desktop portal didn't start the screen cast within \(Self.answerTime.components.seconds) seconds."))
        requests += 1
        let created: (response: UInt32, results: [String: BusValue])?
        do {
            created = try request(ScreenCastPortal.interface, "CreateSession", [], options: ["session_handle_token": .string(ScreenshotPortal.token(requests))], wait: Self.answerTime)
        } catch {
            throw fail(error)
        }
        guard let created else {
            throw late
        }
        let session: String
        do {
            session = try ScreenCastPortal.sessionHandle(response: created.response, results: created.results)
        } catch {
            throw .failed(error)
        }
        var opened = false
        defer {
            if !opened {
                bus.send(BusMessage.call(destination: ScreenshotPortal.service, path: session, interface: ScreenCastPortal.session, member: "Close"))
            }
        }
        let options = ScreenCastPortal.selectOptions(
            types: ScreenCastPortal.sourceTypes(window: window, available: properties.sourceTypes),
            cursorMode: ScreenCastPortal.cursorMode(showsCursor: showsCursor, available: properties.cursorModes), persists: !window, restoreToken: token
        )
        let selected: (response: UInt32, results: [String: BusValue])?
        do {
            selected = try request(ScreenCastPortal.interface, "SelectSources", [.objectPath(session)], options: options, wait: Self.answerTime)
        } catch {
            throw token != nil && ScreenCastPortal.isTokenProblem(name: error.name, message: error.message) ? .tokenRejected : fail(error)
        }
        guard let selected else {
            throw late
        }
        do {
            try ScreenCastPortal.check(selected.response, step: "record the screen")
        } catch {
            // A portal may turn a bad token down in its answer rather than its reply.
            throw token != nil && selected.response == 2 ? .tokenRejected : .failed(error)
        }
        // The dialog shows now, unless a token picks the source.
        let answer: (response: UInt32, results: [String: BusValue])?
        do {
            answer = try request(ScreenCastPortal.interface, "Start", [.objectPath(session), .string("")], options: [:], wait: Self.pickTime)
        } catch {
            throw fail(error)
        }
        guard let answer else {
            throw .failed(.noInput("Nothing was picked in the desktop's dialog within \(Self.pickTime.components.seconds) seconds, so nothing was recorded."))
        }
        let started: ScreenCastPortal.Started
        do {
            started = try ScreenCastPortal.started(response: answer.response, results: answer.results)
        } catch {
            throw .failed(error)
        }
        let remote = BusMessage.call(
            destination: ScreenshotPortal.service, path: ScreenshotPortal.object, interface: ScreenCastPortal.interface, member: "OpenPipeWireRemote",
            [.objectPath(session), .dictionary([:])]
        )
        let reply: BusMessage
        do {
            reply = try bus.call(remote, timeout: .seconds(10))
        } catch {
            throw fail(error)
        }
        guard case let .unixFD(fd)? = reply.arguments.first, fd >= 0 else {
            throw .failed(.io("The desktop portal started the screen cast but gave no PipeWire connection to read it through."))
        }
        opened = true
        return ScreenCast(session: session, started: started, fd: fd)
    }
}
