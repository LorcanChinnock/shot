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
/// `shot serve` saves it in the capture folder instead. libdbus does the talking, without a main loop, on a queue of its
/// own, since a call blocks until the portal answers.
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

    /// How long the portal has to answer a screenshot nobody's asked about.
    static let answerTime = Duration.seconds(30)
    /// How long the user has to pick something in the desktop's dialog, as long as `shot pick` waits.
    static let pickTime = Duration.seconds(ShotCommand.PickOptions.defaultTimeout)
    /// How long a screenshot `displays()` took stays fresh enough for the capture after it.
    static let freshTime = Duration.seconds(2)

    /// Connects to the session bus at `address` and checks the portal can take screenshots. `xwayland` lists and
    /// captures X11 apps' windows.
    init(address: String, xwayland: X11Capturer? = nil) throws(ShotCommandError) {
        bus = try SessionBus(address: address)
        version = try Self.screenshotVersion(on: bus)
        self.xwayland = xwayland
    }

    /// The version of the Screenshot interface the portal on the bus at `address` has, or why there's none.
    static func probe(address: String) -> Result<UInt32, ShotCommandError> {
        Result { () throws(ShotCommandError) in try screenshotVersion(on: try SessionBus(address: address)) }
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
    var limits: [ScreenCapability: String] { [.record: ScreenshotPortal.noRecording] }
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

    /// Calls the portal's `Screenshot` and waits for the `Response` on the request object it names, listening before
    /// the call so the answer can't come first. On `queue`.
    private func takeScreenshot(interactive: Bool) throws(ShotCommandError) -> Bitmap {
        requests += 1
        let token = ScreenshotPortal.token(requests)
        // Every response, rather than the one on the path the token gives, since portals before version 0.9 of the
        // spec make up their own path, which comes only with the reply.
        let rule = "type='signal',interface='\(ScreenshotPortal.request)',member='Response'"
        let call = BusMessage.call(
            destination: ScreenshotPortal.service, path: ScreenshotPortal.object, interface: ScreenshotPortal.interface, member: "Screenshot",
            [.string(""), .dictionary(["handle_token": .string(token), "interactive": .bool(interactive), "modal": .bool(true)])]
        )
        let reply: BusMessage
        do {
            try bus.addMatch(rule)
        } catch {
            throw ScreenshotPortal.problem(name: error.name, message: error.message)
        }
        defer { bus.removeMatch(rule) }
        do {
            reply = try bus.call(call, timeout: .seconds(10))
        } catch {
            throw ScreenshotPortal.problem(name: error.name, message: error.message)
        }
        guard case let .objectPath(handle)? = reply.arguments.first else {
            throw .io("The desktop portal answered the screenshot request with something Shot doesn't understand.")
        }
        let wait = interactive ? Self.pickTime : Self.answerTime
        let deadline = ContinuousClock.now + wait
        while let message = bus.next(until: deadline) {
            guard message.isSignal(ScreenshotPortal.request, "Response"), message.path == handle else {
                continue
            }
            let arguments = message.arguments
            guard case let .uint32(response)? = arguments.first else {
                throw .io("The desktop portal answered the screenshot request with something Shot doesn't understand.")
            }
            var uri: String?
            if arguments.count > 1, case let .dictionary(results) = arguments[1], case let .string(text)? = results["uri"] {
                uri = text
            }
            let path = try ScreenshotPortal.file(response: response, uri: uri)
            defer { try? FileManager.default.removeItem(atPath: path) }
            guard let image = codec.decode(fileAt: URL(fileURLWithPath: path)) else {
                throw .data("Shot couldn't read the screenshot the desktop portal saved at \(path).")
            }
            return image
        }
        // Closes the dialog, so it doesn't wait for the user after the agent has given up.
        bus.send(BusMessage.call(destination: ScreenshotPortal.service, path: handle, interface: ScreenshotPortal.request, member: "Close"))
        throw interactive
            ? .noInput("Nothing was picked in the desktop's screenshot dialog within \(wait.components.seconds) seconds, so nothing was captured.")
            : .unavailable("The desktop portal didn't take the screenshot within \(wait.components.seconds) seconds.")
    }
}
