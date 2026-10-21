import CDBus
import Foundation
import Synchronization
import Testing
@testable import ShotCore
@testable import ShotCoreLinux

/// A session bus of its own, from dbus-daemon, at a socket nothing else uses, stopped when it's released.
final class TestBus: @unchecked Sendable {
    static let executable = TestServer.executable("/usr/bin/dbus-daemon", "/usr/local/bin/dbus-daemon")
    let address: String
    private let folder: URL
    private let pid: pid_t

    init() async throws {
        let executable = try #require(Self.executable)
        // A short folder of its own, since a socket's whole path must fit in 107 bytes.
        folder = URL(fileURLWithPath: "/tmp/sb-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        address = "unix:path=\(folder.path)/bus"
        pid = try TestServer.spawn(executable, ["--session", "--nofork", "--nopidfile", "--address=\(address)"])
        for _ in 0 ..< 200 where TestServer.isRunning(pid) {
            if (try? SessionBus(address: address)) != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        TestServer.stop(pid)
        throw ShotCommandError.internal("dbus-daemon didn't start.")
    }

    deinit {
        TestServer.stop(pid)
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Stands in for xdg-desktop-portal on a test bus: answers the Screenshot interface's version, and each `Screenshot`
/// with `image`, saved to a file of its own, or with `response` when that isn't 0, as a backend would after the user
/// picks or cancels. Without `screenshot`, it's a portal with no Screenshot backend.
final class FakePortal: @unchecked Sendable {
    struct Options {
        var screenshot = true
        var response: UInt32 = 0
        /// Answers on a path it makes up, as portals did before handle tokens.
        var ownPath = false
        var image = Bitmap(width: 64, height: 48, scale: 1, pixels: FakePortal.pattern(width: 64, height: 48))!
    }

    private let bus: SessionBus
    private let options: Options
    private let folder: URL
    private let stopped = Atomic(false)
    private let finished = DispatchSemaphore(value: 0)
    /// Whether each `Screenshot` asked for the dialog, in order.
    let requests = Mutex<[Bool]>([])
    /// The files it saved screenshots in.
    let files = Mutex<[String]>([])

    init(on address: String, _ options: Options = Options()) throws {
        bus = try SessionBus(address: address)
        self.options = options
        folder = try temporaryFolder()
        var error = DBusError()
        dbus_error_init(&error)
        defer { dbus_error_free(&error) }
        let owner = dbus_bus_request_name(bus.connection, ScreenshotPortal.service, UInt32(DBUS_NAME_FLAG_DO_NOT_QUEUE), &error)
        try #require(owner == DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER, "\(SessionBus.text(error.message))")
        // A thread of its own, since it blocks waiting for messages.
        Thread { [self] in
            while !stopped.load(ordering: .relaxed) {
                if let message = bus.next(until: .now + .milliseconds(50)), message.type == DBUS_MESSAGE_TYPE_METHOD_CALL {
                    answer(message)
                }
            }
            finished.signal()
        }.start()
    }

    func stop() {
        stopped.store(true, ordering: .relaxed)
        finished.wait()
        try? FileManager.default.removeItem(at: folder)
    }

    /// Each pixel's red and green are its column and row, so a crop shows where it came from.
    static func pattern(width: Int, height: Int) -> Data {
        Data((0 ..< height).flatMap { y in (0 ..< width).flatMap { x in [UInt8(x), UInt8(y), 99, 255] } })
    }

    private func answer(_ call: BusMessage) {
        switch (call.interface, call.member) {
        case ("org.freedesktop.DBus.Properties", "Get"):
            guard options.screenshot, call.arguments.first == .string(ScreenshotPortal.interface) else {
                return reply(error: "org.freedesktop.DBus.Error.InvalidArgs", "No such interface", to: call)
            }
            reply([.variant(.uint32(1))], to: call)
        case (ScreenshotPortal.interface, "Screenshot"):
            guard options.screenshot else {
                return reply(error: "org.freedesktop.DBus.Error.UnknownMethod", "No such method", to: call)
            }
            let arguments = call.arguments
            guard arguments.count == 2, case let .dictionary(asked) = arguments[1], case let .string(token)? = asked["handle_token"],
                  let sender = dbus_message_get_sender(call.pointer)
            else {
                return reply(error: "org.freedesktop.DBus.Error.InvalidArgs", "Bad arguments", to: call)
            }
            let interactive = asked["interactive"] == .bool(true)
            let count = requests.withLock {
                $0.append(interactive)
                return $0.count
            }
            // Where the spec says a request with this token is answered: the sender's unique name, such as :1.42,
            // without its colon and with underscores for dots.
            let name = String(cString: sender).dropFirst().replacingOccurrences(of: ".", with: "_")
            let path = "/org/freedesktop/portal/desktop/request/" + (options.ownPath ? "fake/\(count)" : "\(name)/\(token)")
            reply([.objectPath(path)], to: call)
            var results: [String: BusValue] = [:]
            if options.response == 0 {
                let file = folder.appendingPathComponent("Screenshot \(count).png")
                let data = PNGJPEGCodec().encode(options.image, as: .png, quality: 1, metadata: ImageMetadata())
                try? data?.write(to: file)
                files.withLock { $0.append(file.path) }
                results["uri"] = .string(file.absoluteString)
            }
            let signal = BusMessage(dbus_message_new_signal(path, ScreenshotPortal.request, "Response"))
            signal.append([.uint32(options.response), .dictionary(results)])
            bus.send(signal)
        default:
            reply(error: "org.freedesktop.DBus.Error.UnknownMethod", "No such method", to: call)
        }
    }

    private func reply(_ arguments: [BusValue], to call: BusMessage) {
        let reply = BusMessage(dbus_message_new_method_return(call.pointer))
        reply.append(arguments)
        bus.send(reply)
    }

    private func reply(error name: String, _ message: String, to call: BusMessage) {
        bus.send(BusMessage(dbus_message_new_error(call.pointer, name, message)))
    }
}

/// CI installs dbus-daemon, so there a missing one fails rather than skips.
private let hasDBus = TestBus.executable != nil || ProcessInfo.processInfo.environment["CI"] != nil

/// One at a time, so a single bus competes with the other tests for CI's few cores.
@Suite(.serialized, .enabled(if: hasDBus, "dbus-daemon isn't installed")) struct PortalCapturerTests {
    @Test func portalCapturerCapturesTheScreenAndAnAreaWithoutAsking() async throws {
        let bus = try await TestBus()
        let portal = try FakePortal(on: bus.address)
        defer { portal.stop() }
        let capturer = try PortalCapturer(address: bus.address)
        #expect(capturer.name == "portal" && capturer.limits == [.record: ScreenshotPortal.noRecording] && capturer.version == 1)
        #expect(LinuxScreen.screenshotPortal(environment: ["XDG_SESSION_TYPE": "wayland", "DBUS_SESSION_BUS_ADDRESS": bus.address]) == .success(1))

        // The first listing takes a screenshot to learn the size, which the capture after it uses.
        let displays = try await capturer.displays()
        #expect(displays == [ScreenDisplay(name: "screen", frame: CGRect(x: 0, y: 0, width: 64, height: 48))])
        let screen = try await capturer.capture(display: displays[0])
        #expect(screen.width == 64 && screen.height == 48 && screen[10, 20] == (10, 20, 99, 255))
        #expect(portal.requests.withLock { $0 } == [false])
        // Later ones reuse the size, and each capture is new.
        #expect(try await capturer.displays() == displays)
        let area = try await capturer.capture(area: CGRect(x: 40, y: 30, width: 50, height: 10))
        #expect(area.width == 24 && area.height == 10 && area[0, 0] == (40, 30, 99, 255))
        #expect(portal.requests.withLock { $0 } == [false, false])
        await #expect(throws: ShotCommandError.data("The area at 70,0, 10×10 points, is off the screen.")) {
            try await capturer.capture(area: CGRect(x: 70, y: 0, width: 10, height: 10))
        }
        // The portal's files are moved into the capture folder, not left behind.
        #expect(portal.files.withLock { $0 }.allSatisfy { !FileManager.default.fileExists(atPath: $0) })

        #expect(try await capturer.windows().isEmpty)
        #expect(capturer.windowsNote == ScreenshotPortal.windowsNote(xwayland: false))
    }

    @Test func portalCapturerHasTheUserPickAWindow() async throws {
        let bus = try await TestBus()
        let portal = try FakePortal(on: bus.address)
        defer { portal.stop() }
        let capturer = try PortalCapturer(address: bus.address)
        let picked = try #require(try await capturer.capturePicked())
        #expect(picked.width == 64 && picked.height == 48)
        #expect(portal.requests.withLock { $0 } == [true])
    }

    @Test func shotServeCapturesAWaylandSessionThroughThePortal() async throws {
        let bus = try await TestBus()
        let portal = try FakePortal(on: bus.address)
        defer { portal.stop() }
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.set(root.path, forKey: PreferenceKey.saveFolder)
        store.set(true, forKey: PreferenceKey.saveAfterCapture)
        store.set(true, forKey: PreferenceKey.agentCapture)
        defer {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: LinuxSettings.file(suite: suite))
        }
        let capturer = LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "wayland", "DBUS_SESSION_BUS_ADDRESS": bus.address])
        #expect(capturer.name == "portal")
        // Without registering defaults, which the whole process shares on Linux, so RegisteredDefaultsTests keeps them to
        // itself. The keys the daemon reads are set above, or fall back to the defaults.
        let daemon = AgentDaemon(capturer: capturer, projects: nil, version: "0.7.0") {
            Preferences(store: UserDefaults(suiteName: suite)!)
        }

        guard case let .success(listed) = await daemon.handle(AgentRequest(.windows)) else {
            Issue.record("No windows.")
            return
        }
        #expect(listed["windows"] == .array([]))
        #expect(listed["note"] == .string(ScreenshotPortal.windowsNote(xwayland: false)))

        let area = await daemon.handle(AgentRequest(.capture, target: AgentTarget(display: 1, rect: [8, 4, 16, 8])))
        guard case let .success(answer) = area else {
            Issue.record("The capture failed: \(area)")
            return
        }
        #expect(answer["size"] == .object(["width": .number(16), "height": .number(8)]))
        let path = try #require(answer["path"]?.string)
        let image = try #require(PNGJPEGCodec().decode(fileAt: URL(fileURLWithPath: path)))
        #expect(image[0, 0] == (8, 4, 99, 255))

        let window = await daemon.handle(AgentRequest(.capture, target: AgentTarget(window: "Terminal")))
        guard case let .success(picked) = window else {
            Issue.record("The capture failed: \(window)")
            return
        }
        #expect(picked["window"] == .object(["picked": .bool(true)]) && picked["note"] == .string(ScreenshotPortal.pickedNote))
        #expect(portal.requests.withLock { $0 }.last == true)
    }

    @Test func portalCapturerSaysWhyItCantCapture() async throws {
        let bus = try await TestBus()
        // Nothing owns the portal's name, and this bus can't start one.
        await #expect(throws: ScreenshotPortal.problem(name: "org.freedesktop.DBus.Error.ServiceUnknown", message: "")) {
            try PortalCapturer(address: bus.address)
        }
        let none = LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "wayland", "DBUS_SESSION_BUS_ADDRESS": bus.address])
        #expect(none.name == "none" && none.limits[.captureDisplay]?.hasPrefix("The desktop portal isn't running") == true)

        let unreachable = try #require(throws: ShotCommandError.self) { try PortalCapturer(address: "unix:path=/tmp/no-such-bus-\(UUID().uuidString.prefix(8))") }
        #expect(unreachable.message.hasPrefix("Shot couldn't connect to the session bus at unix:path=/tmp/no-such-bus-"))

        let backendless = try FakePortal(on: bus.address, FakePortal.Options(screenshot: false))
        await #expect(throws: ScreenshotPortal.problem(name: "org.freedesktop.DBus.Error.InvalidArgs", message: "")) {
            try PortalCapturer(address: bus.address)
        }
        backendless.stop()
    }

    @Test func portalCapturerSaysWhenTheUserCancels() async throws {
        let bus = try await TestBus()
        let portal = try FakePortal(on: bus.address, FakePortal.Options(response: 1))
        defer { portal.stop() }
        let capturer = try PortalCapturer(address: bus.address)
        await #expect(throws: ShotCommandError.noInput("The screenshot was cancelled or not allowed in the desktop's dialog, so nothing was captured.")) {
            try await capturer.capturePicked()
        }
    }

    @Test func portalCapturerFollowsARequestPathThePortalMadeUp() async throws {
        let bus = try await TestBus()
        let portal = try FakePortal(on: bus.address, FakePortal.Options(ownPath: true))
        defer { portal.stop() }
        let capturer = try PortalCapturer(address: bus.address)
        #expect(try await capturer.capture(area: CGRect(x: 0, y: 0, width: 4, height: 4)).width == 4)
    }
}
