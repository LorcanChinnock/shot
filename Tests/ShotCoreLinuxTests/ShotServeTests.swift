import Foundation
import Testing
@testable import ShotCore
@testable import ShotCoreLinux

/// Holds a capture until it's opened, so a test can send a second request while the first runs.
private actor Gate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var isEntered = false

    func wait() async {
        isEntered = true
        entered?.resume()
        entered = nil
        await withCheckedContinuation { waiting = $0 }
    }

    func untilEntered() async {
        guard !isEntered else {
            return
        }
        await withCheckedContinuation { entered = $0 }
    }

    func open() {
        waiting?.resume()
        waiting = nil
    }
}

/// One 200×100 display at 2 pixels a point and two windows, Terminal in front. Each capture is grey, at the size its
/// target is in pixels.
private struct FakeScreen: ScreenCapturer {
    var limits: [ScreenCapability: String] = [:]
    var gate: Gate?

    var name: String { "fake" }

    func displays() -> [ScreenDisplay] {
        [ScreenDisplay(name: "Built-in", frame: CGRect(x: 0, y: 0, width: 200, height: 100), scale: 2)]
    }

    func windows() -> [ScreenWindow] {
        [
            ScreenWindow(id: 7, app: "Terminal", title: "~", appID: "org.gnome.Terminal", frame: CGRect(x: 10, y: 10, width: 60, height: 40)),
            ScreenWindow(id: 9, app: "Firefox", title: "Shot — docs", appID: "firefox", frame: CGRect(x: 80, y: 0, width: 120, height: 100)),
        ]
    }

    func capture(display: ScreenDisplay) -> Bitmap {
        Self.grey(display.frame)
    }

    func capture(window: ScreenWindow) async -> Bitmap {
        await gate?.wait()
        return Self.grey(window.frame)
    }

    func capture(area: CGRect) -> Bitmap {
        Self.grey(area)
    }

    static func grey(_ points: CGRect) -> Bitmap {
        let width = Int(points.width * 2), height = Int(points.height * 2)
        return Bitmap(width: width, height: height, scale: 2, pixels: Data(repeating: 128, count: width * height * 4))!
    }
}

/// `shot serve` with `capturer` on a socket of its own, saving to a capture folder of its own, with settings that
/// `configure` can change, and a project store.
private final class Serve: @unchecked Sendable {
    let root: URL
    let folder: URL
    let socket: URL
    let projects: ProjectStore
    let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
    let server: AgentSocket.Server

    init(_ capturer: any ScreenCapturer = FakeScreen(), user: uid_t = getuid(), configure: (UserDefaults) -> Void = { _ in }) throws {
        root = try temporaryFolder()
        folder = root.appendingPathComponent("Shot", isDirectory: true)
        // A short folder of its own, since a socket's whole path must fit in 107 bytes.
        socket = URL(fileURLWithPath: "/tmp/ss-\(UUID().uuidString.prefix(8))/agent.sock")
        projects = ProjectStore(folder: root.appendingPathComponent("Projects", isDirectory: true))
        let store = try #require(UserDefaults(suiteName: suite))
        store.set(folder.path, forKey: PreferenceKey.saveFolder)
        store.set(true, forKey: PreferenceKey.saveAfterCapture)
        store.set(true, forKey: PreferenceKey.agentCapture)
        configure(store)
        store.synchronize()
        let suite = suite
        let daemon = AgentDaemon(capturer: capturer, codec: PNGJPEGCodec(), projects: projects, version: "0.7.0") {
            let store = UserDefaults(suiteName: suite)!
            Preferences.registerDefaults(in: store)
            return Preferences(store: store)
        }
        server = AgentSocket.Server(url: socket, user: user) { request in
            await daemon.handle(request)
        }
        try server.start()
    }

    func send(_ request: AgentRequest) async throws(ShotCommandError) -> [String: JSONValue] {
        try await AgentSocket.send(request, to: socket, timeout: .seconds(10))
    }

    func failure(_ request: AgentRequest) async -> ShotCommandError? {
        do {
            _ = try await send(request)
            return nil
        } catch {
            return error
        }
    }

    deinit {
        server.stop()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: LinuxSettings.file(suite: suite))
        try? FileManager.default.removeItem(at: socket.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: root)
    }
}

@Test func shotServeSavesAWindowsScreenshotToTheCaptureFolder() async throws {
    let serve = try Serve()
    var request = AgentRequest(.capture, target: AgentTarget(window: "terminal"))
    request.origin = ProjectOrigin(via: .cli, action: "capture")
    let answer = try await serve.send(request)

    let path = try #require(answer["path"]?.string)
    let file = URL(fileURLWithPath: path)
    #expect(file.deletingLastPathComponent().path == serve.folder.path)
    #expect(file.lastPathComponent.hasPrefix("Shot ") && file.pathExtension == "png")
    #expect(answer["size"] == .object(["width": .number(120), "height": .number(80)]))
    #expect(answer["window"] == .object(["app": .string("Terminal"), "title": .string("~")]))
    let bytes = try #require(FileManager.default.attributesOfItem(atPath: path)[.size] as? Int)
    #expect(answer["bytes"] == .number(Double(bytes)))

    let codec = PNGJPEGCodec()
    #expect(codec.scale(ofFileAt: file) == 2)
    let record = try #require(codec.record(ofFileAt: file))
    #expect(record.kind == "image")
    #expect(record.size == CaptureRecord.Size(width: 120, height: 80))
    #expect(record.source == CaptureRecord.Source(
        mode: "window", app: "Terminal", bundleID: "org.gnome.Terminal", windowTitle: "~", screenFrame: CaptureRecord.Frame(x: 10, y: 10, width: 60, height: 40)
    ))
    let entry = try #require(serve.projects.entry(for: file))
    #expect(entry.origin.via == .cli && entry.origin.action == "capture")
    #expect(codec.projectID(ofFileAt: file) != nil)
}

@Test func shotServeCapturesPartOfADisplayAndWaitsForItToSettle() async throws {
    let serve = try Serve { $0.set("jpeg", forKey: PreferenceKey.imageFormat) }
    let answer = try await serve.send(AgentRequest(.capture, target: AgentTarget(display: 1, rect: [150, 80, 100, 100], waitStable: 1)))
    // The rect is cut to the display, which is 200×100 points.
    #expect(answer["size"] == .object(["width": .number(100), "height": .number(40)]))
    #expect(answer["window"] == .object(["display": .number(1), "name": .string("Built-in")]))
    let file = URL(fileURLWithPath: try #require(answer["path"]?.string))
    #expect(file.pathExtension == "jpg")
    #expect(PNGJPEGCodec().record(ofFileAt: file)?.source == CaptureRecord.Source(mode: "fullscreen", screenFrame: CaptureRecord.Frame(x: 150, y: 80, width: 50, height: 20)))
}

@Test func shotServeDownscalesToPointsWhenSettingsAskIt() async throws {
    let serve = try Serve { $0.set(true, forKey: PreferenceKey.downscaleRetina) }
    let answer = try await serve.send(AgentRequest(.capture, target: AgentTarget(display: 1)))
    #expect(answer["size"] == .object(["width": .number(200), "height": .number(100)]))
    #expect(PNGJPEGCodec().scale(ofFileAt: URL(fileURLWithPath: try #require(answer["path"]?.string))) == 1)
}

@Test func shotServeListsTheWindowsAndDisplays() async throws {
    let serve = try Serve()
    let answer = try await serve.send(AgentRequest(.windows))
    #expect(answer["windows"] == WindowMatch.json(FakeScreen().windows().map(\.candidate), frontmostBundleID: "org.gnome.Terminal"))
    #expect(answer["displays"] == .array([.object([
        "display": .number(1), "name": .string("Built-in"), "size": .object(["width": .number(200), "height": .number(100)]), "scale": .number(2), "main": .bool(true),
    ])]))
    let status = try await serve.send(AgentRequest(.status))
    #expect(status == ["capturing": .bool(false), "recording": .null, "version": .string("0.7.0"), "capturer": .string("fake"), "limits": .object([:])])
}

@Test func shotServeRefusesWhatItCantOrMayNotDo() async throws {
    let off = try Serve { $0.set(false, forKey: PreferenceKey.agentCapture) }
    #expect(await off.failure(AgentRequest(.capture, target: AgentTarget(display: 1))) == .unavailable(AgentSocket.turnedOff))
    #expect(await off.failure(AgentRequest(.windows)) == .unavailable(AgentSocket.turnedOff))
    #expect(try await off.send(AgentRequest(.status))["capturer"] == .string("fake"))
    #expect(!FileManager.default.fileExists(atPath: off.folder.path))

    let wayland = try Serve(FakeScreen(limits: [.captureWindow: "Wayland asks before each window."]))
    #expect(await wayland.failure(AgentRequest(.capture, target: AgentTarget(window: "Terminal"))) == .unavailable("Wayland asks before each window."))
    #expect(try await wayland.send(AgentRequest(.capture, target: AgentTarget(display: 1)))["path"] != nil)

    let serve = try Serve()
    #expect(await serve.failure(AgentRequest(.record, target: AgentTarget(window: "Terminal"))) == .notOnLinuxYet)
    #expect(await serve.failure(AgentRequest(.pick)) == .notOnLinuxYet)
    #expect(await serve.failure(AgentRequest(.capture, target: AgentTarget(display: 2))) == .noInput("There's no display 2; this computer has 1. shot windows lists them."))
    #expect(await serve.failure(AgentRequest(.capture, target: AgentTarget(display: 1, rect: [300, 0, 10, 10]))) == .data("The rect 300,0,10,10 is off display 1, which is 200×100 points."))
    let missing = try #require(await serve.failure(AgentRequest(.capture, target: AgentTarget(window: "Calculator"))))
    #expect(missing.message.hasPrefix("No open window matches \"Calculator\". Open windows, front to back:\n  Terminal — ~\n  Firefox — Shot — docs"))
}

@Test func shotServeTurnsAwayASecondCaptureWhileOneRuns() async throws {
    let gate = Gate()
    let serve = try Serve(FakeScreen(gate: gate))
    async let first = serve.send(AgentRequest(.capture, target: AgentTarget(window: "Terminal")))
    await gate.untilEntered()
    #expect(await serve.failure(AgentRequest(.capture, target: AgentTarget(display: 1))) == .busy("Shot is in the middle of a capture; try again once it's done."))
    #expect(try await serve.send(AgentRequest(.status))["capturing"] == .bool(true))
    // Listing needs no capture, so it's answered meanwhile.
    #expect(try await serve.send(AgentRequest(.windows))["windows"] != nil)
    await gate.open()
    #expect(try await first["path"] != nil)
    #expect(try await serve.send(AgentRequest(.capture, target: AgentTarget(display: 1)))["path"] != nil)
}

@Test func shotServeAnswersOnlyItsOwnUser() async throws {
    // The server expects another user, so this one's connection is closed unanswered, as another user's would be.
    let serve = try Serve(user: getuid() + 1)
    #expect(await serve.failure(AgentRequest(.status)) == .io("Shot closed the connection without a usable answer"))
    #expect(try await Serve().send(AgentRequest(.status))["version"] == .string("0.7.0"))
}

@Test func shotServeSaysWhenNothingCapturesTheSession() async throws {
    #expect(LinuxScreen.capturer(environment: [:]).limits[.captureDisplay] == "XDG_SESSION_TYPE isn't set, so Shot can't tell which session to capture.")
    #expect(LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "tty"]).limits[.listWindows] == "XDG_SESSION_TYPE is tty, and Shot can capture only an X11 or Wayland session.")
    let serve = try Serve(LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "x11"]))
    #expect(await serve.failure(AgentRequest(.windows)) == .unavailable("Shot can't capture an X11 session yet."))
    #expect(await serve.failure(AgentRequest(.capture, target: AgentTarget(display: 1))) == .unavailable("Shot can't capture an X11 session yet."))
    let status = try await serve.send(AgentRequest(.status))
    #expect(status["capturer"] == .string("none"))
    #expect(status["limits"]?["captureWindow"] == .string("Shot can't capture an X11 session yet."))
}

@Test func theMCPToolsThatCaptureAskShotServeOnLinux() async throws {
    let serve = try Serve()
    let socket = serve.socket
    let tools = AgentTools.live(folder: serve.folder, projects: serve.projects) { request throws(ShotCommandError) in
        try await AgentSocket.send(request, to: socket, timeout: .seconds(10))
    }
    let listed = await tools.call(AgentTools.listWindows, .object([:]))
    #expect(listed.isError != true, "\(listed)")
    let captured = await tools.call(AgentTools.captureWindow, .object(["window": .string("Firefox")]))
    #expect(captured.isError != true, "\(captured)")
    #expect(try FileManager.default.contentsOfDirectory(atPath: serve.folder.path).count == 1)
}
