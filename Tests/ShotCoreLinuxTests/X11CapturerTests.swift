import CXCB
import Foundation
import Testing
@testable import ShotCore
@testable import ShotCoreLinux

/// An Xvfb of its own, 640×480 with a black root, on a display nothing else uses, stopped when it's released.
final class XServer: @unchecked Sendable {
    static let executable = TestServer.executable("/usr/bin/Xvfb", "/usr/local/bin/Xvfb")
    let display: String
    private let pid: pid_t

    init() async throws {
        let executable = try #require(Self.executable)
        for _ in 0 ..< 10 {
            let number = Int.random(in: 100 ..< 20000)
            guard !FileManager.default.fileExists(atPath: "/tmp/.X\(number)-lock") else {
                continue
            }
            // Without -noreset, the server resets when the check below disconnects, dropping whoever connects next.
            let pid = try TestServer.spawn(executable, [":\(number)", "-screen", "0", "640x480x24", "-br", "-nolisten", "tcp", "-noreset"])
            // Something else may have taken the display, so Xvfb quits and the next number is tried.
            for _ in 0 ..< 200 where TestServer.isRunning(pid) {
                if let connection = xcb_connect(":\(number)", nil) {
                    defer { xcb_disconnect(connection) }
                    if xcb_connection_has_error(connection) == 0 {
                        display = ":\(number)"
                        self.pid = pid
                        return
                    }
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            TestServer.stop(pid)
        }
        throw ShotCommandError.internal("Xvfb didn't start.")
    }

    deinit {
        TestServer.stop(pid)
    }
}

/// A client of the server that puts windows on it, and stands in for a window manager by listing them in
/// `_NET_CLIENT_LIST`.
private final class Desktop: @unchecked Sendable {
    let connection: OpaquePointer
    let root: xcb_window_t
    let visual: xcb_visualid_t

    init(_ server: XServer) throws {
        connection = try #require(xcb_connect(server.display, nil))
        let screen = try #require(xcb_setup_roots_iterator(xcb_get_setup(connection)).data)
        root = screen.pointee.root
        visual = screen.pointee.root_visual
    }

    deinit {
        xcb_disconnect(connection)
    }

    /// A window filled with `color`, as 0xRRGGBB, mapped unless `mapped` is false.
    @discardableResult
    func window(
        _ frame: CGRect, color: UInt32, in parent: xcb_window_t? = nil, title: String? = nil, oldTitle: String? = nil, windowClass: String? = nil,
        pid: Int32? = nil, type: String? = nil, popup: Bool = false, mapped: Bool = true
    ) -> xcb_window_t {
        let id = xcb_generate_id(connection)
        let values: [UInt32] = [color, popup ? 1 : 0]
        let mask = XCB_CW_BACK_PIXEL.rawValue | XCB_CW_OVERRIDE_REDIRECT.rawValue
        xcb_create_window(
            connection, 0, id, parent ?? root, Int16(frame.minX), Int16(frame.minY), UInt16(frame.width), UInt16(frame.height), 0,
            UInt16(XCB_WINDOW_CLASS_INPUT_OUTPUT.rawValue), visual, mask, values
        )
        if let title {
            set(id, "_NET_WM_NAME", type: atom("UTF8_STRING"), bytes: Array(title.utf8))
        }
        if let oldTitle {
            set(id, "WM_NAME", type: XCB_ATOM_STRING.rawValue, bytes: Array(oldTitle.utf8))
        }
        if let windowClass {
            set(id, "WM_CLASS", type: XCB_ATOM_STRING.rawValue, bytes: Array(windowClass.utf8))
        }
        if let pid {
            set(id, "_NET_WM_PID", type: XCB_ATOM_CARDINAL.rawValue, values: [UInt32(pid)])
        }
        if let type {
            set(id, "_NET_WM_WINDOW_TYPE", type: XCB_ATOM_ATOM.rawValue, values: [atom("_NET_WM_WINDOW_TYPE_\(type)")])
        }
        if mapped {
            xcb_map_window(connection, id)
        }
        return id
    }

    func set(_ window: xcb_window_t, _ name: String, type: xcb_atom_t, bytes: [UInt8]) {
        xcb_change_property(connection, UInt8(XCB_PROP_MODE_REPLACE.rawValue), window, atom(name), type, 8, UInt32(bytes.count), bytes)
    }

    func set(_ window: xcb_window_t, _ name: String, type: xcb_atom_t, values: [UInt32]) {
        xcb_change_property(connection, UInt8(XCB_PROP_MODE_REPLACE.rawValue), window, atom(name), type, 32, UInt32(values.count), values)
    }

    func listClients(_ windows: [xcb_window_t]) {
        set(root, "_NET_CLIENT_LIST", type: XCB_ATOM_WINDOW.rawValue, values: windows)
    }

    func forgetClients() {
        xcb_delete_property(connection, root, atom("_NET_CLIENT_LIST"))
    }

    func atom(_ name: String) -> xcb_atom_t {
        let reply = xcb_intern_atom_reply(connection, xcb_intern_atom(connection, 0, UInt16(name.utf8.count), name), nil)
        defer { free(reply) }
        return reply?.pointee.atom ?? 0
    }

    /// Waits until the server has done everything asked of it.
    func sync() {
        free(xcb_get_input_focus_reply(connection, xcb_get_input_focus(connection), nil))
    }
}

/// Red, with blue over its right part, a green window in a grey frame with a shadow of its own, and windows that aren't
/// listed: a tiny one, a dock, an unmapped one and a popup.
private struct Scene {
    let server: XServer
    let desktop: Desktop
    let capturer: X11Capturer
    let red, blue, green: xcb_window_t

    init() async throws {
        server = try await XServer()
        desktop = try Desktop(server)
        // Before the windows, so the server keeps their pictures from the start.
        capturer = try X11Capturer(display: server.display)
        red = desktop.window(CGRect(x: 10, y: 20, width: 200, height: 100), color: 0xFF0000, title: "Shot test — red", windowClass: "red\0Red\0", pid: getpid())
        blue = desktop.window(CGRect(x: 150, y: 60, width: 120, height: 80), color: 0x0000FF, oldTitle: "blue", windowClass: "blue\0Blue\0")
        let frame = desktop.window(CGRect(x: 400, y: 300, width: 160, height: 120), color: 0x808080)
        green = desktop.window(CGRect(x: 5, y: 25, width: 150, height: 90), color: 0x00FF00, in: frame, title: "green", windowClass: "green\0Green\0")
        desktop.set(green, "_GTK_FRAME_EXTENTS", type: XCB_ATOM_CARDINAL.rawValue, values: [5, 5, 5, 5])
        let tiny = desktop.window(CGRect(x: 600, y: 10, width: 20, height: 20), color: 0xFFFFFF, title: "tiny")
        let dock = desktop.window(CGRect(x: 0, y: 456, width: 640, height: 24), color: 0xFFFFFF, title: "dock", type: "DOCK")
        let unmapped = desktop.window(CGRect(x: 300, y: 200, width: 100, height: 100), color: 0xFFFFFF, title: "unmapped", mapped: false)
        desktop.window(CGRect(x: 500, y: 100, width: 100, height: 100), color: 0xFFFFFF, popup: true)
        desktop.listClients([red, blue, green, tiny, dock, unmapped])
        desktop.sync()
    }
}

/// CI installs Xvfb, so there a missing one fails rather than skips.
private let hasXvfb = XServer.executable != nil || ProcessInfo.processInfo.environment["CI"] != nil

/// One at a time, so a single Xvfb competes with the other tests for CI's few cores.
@Suite(.serialized, .enabled(if: hasXvfb, "Xvfb isn't installed")) struct X11CapturerTests {
    @Test func x11CapturerListsTheWindowsAndDisplays() async throws {
        let scene = try await Scene()
        let capturer = scene.capturer
        #expect(capturer.name == "x11" && capturer.limits.isEmpty)
        #expect(try await capturer.displays() == [ScreenDisplay(name: "screen", frame: CGRect(x: 0, y: 0, width: 640, height: 480))])

        let process = try String(contentsOfFile: "/proc/self/comm", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(try await capturer.windows() == [
            // Inside its frame, without its shadow.
            ScreenWindow(id: scene.green, app: "Green", title: "green", appID: "Green", frame: CGRect(x: 410, y: 330, width: 140, height: 80)),
            ScreenWindow(id: scene.blue, app: "Blue", title: "blue", appID: "Blue", frame: CGRect(x: 150, y: 60, width: 120, height: 80)),
            ScreenWindow(id: scene.red, app: process, title: "Shot test — red", appID: "Red", frame: CGRect(x: 10, y: 20, width: 200, height: 100)),
        ])

        // Without a window manager, the root's children are the windows, frames included.
        scene.desktop.forgetClients()
        scene.desktop.sync()
        #expect(try await capturer.windows().map(\.frame) == [
            CGRect(x: 400, y: 300, width: 160, height: 120), CGRect(x: 150, y: 60, width: 120, height: 80), CGRect(x: 10, y: 20, width: 200, height: 100),
        ])
    }

    @Test func x11CapturerCapturesADisplayAWindowAndAnArea() async throws {
        let scene = try await Scene()
        let capturer = scene.capturer
        let red: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255), blue: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
        let green: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255), black: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 255)

        let display = try await capturer.capture(display: try await capturer.displays()[0])
        #expect(display.width == 640 && display.height == 480 && display.scale == 1)
        #expect(display[20, 30] == red && display[160, 70] == blue && display[415, 335] == green && display[5, 5] == black)

        let windows = try await capturer.windows()
        let behind = try await capturer.capture(window: try #require(windows.first { $0.id == scene.red }))
        #expect(behind.width == 200 && behind.height == 100)
        // Where blue covers it, red is still red.
        #expect(behind[0, 0] == red && behind[145, 45] == red && behind[199, 99] == red)

        let framed = try await capturer.capture(window: try #require(windows.first { $0.id == scene.green }))
        #expect(framed.width == 140 && framed.height == 80)
        #expect(framed[0, 0] == green && framed[139, 79] == green)

        let area = try await capturer.capture(area: CGRect(x: 140, y: 50, width: 40, height: 30))
        #expect(area.width == 40 && area.height == 30)
        #expect(area[0, 0] == red && area[39, 29] == blue)
        await #expect(throws: ShotCommandError.data("The area at 700,0, 10×10 points, is off the screen.")) {
            try await capturer.capture(area: CGRect(x: 700, y: 0, width: 10, height: 10))
        }

        var gone = windows[0]
        gone.id = 0x7FFF_FFFF
        await #expect(throws: ShotCommandError.noInput("Green — green closed before Shot could capture it.")) {
            try await capturer.capture(window: gone)
        }
    }

    @Test func shotServeSavesAnX11WindowCoveredByAnother() async throws {
        let scene = try await Scene()
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
        let capturer = LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "x11", "DISPLAY": scene.server.display])
        // Without registering defaults, which the whole process shares on Linux, so RegisteredDefaultsTests keeps them to
        // itself. The keys the daemon reads are set above, or fall back to the defaults.
        let daemon = AgentDaemon(capturer: capturer, codec: PNGJPEGCodec(), projects: nil, version: "0.7.0") {
            Preferences(store: UserDefaults(suiteName: suite)!)
        }

        let response = await daemon.handle(AgentRequest(.capture, target: AgentTarget(window: "shot test")))
        guard case let .success(answer) = response else {
            Issue.record("The capture failed: \(response)")
            return
        }
        #expect(answer["size"] == .object(["width": .number(200), "height": .number(100)]))
        let path = try #require(answer["path"]?.string)
        let image = try #require(PNGJPEGCodec().decode(fileAt: URL(fileURLWithPath: path)))
        #expect(image[145, 45] == (255, 0, 0, 255))
        guard case let .success(status) = await daemon.handle(AgentRequest(.status)) else {
            Issue.record("No status.")
            return
        }
        #expect(status["capturer"] == .string("x11") && status["limits"] == .object([:]))
    }

    @Test func portalCapturerListsAndCapturesX11AppsThroughXWayland() async throws {
        let scene = try await Scene()
        let bus = try await TestBus()
        let portal = try FakePortal(on: bus.address)
        defer { portal.stop() }
        let capturer = LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "wayland", "DBUS_SESSION_BUS_ADDRESS": bus.address, "DISPLAY": scene.server.display])
        #expect(capturer.name == "portal" && capturer.windowsNote == ScreenshotPortal.windowsNote(xwayland: true))
        let windows = try await capturer.windows()
        #expect(windows.map(\.id) == [scene.green, scene.blue, scene.red])
        // Silently, without the portal, and whole behind blue.
        let red = try await capturer.capture(window: windows[2])
        #expect(red.width == 200 && red.height == 100 && red[145, 45] == (255, 0, 0, 255))
        #expect(portal.requests.withLock { $0 }.isEmpty)
    }
}

@Test func linuxScreenSaysWhyItCantReachTheXServer() {
    #expect(LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "x11"]).limits[.captureWindow]
        == "DISPLAY isn't set, so Shot can't tell which X server to capture. Run shot from a terminal in your X11 desktop session.")
    let missing = LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "X11", "DISPLAY": ":29999"])
    #expect(missing.name == "none")
    #expect(missing.limits[.listWindows] == "Shot couldn't connect to the X server at DISPLAY :29999.")
}
