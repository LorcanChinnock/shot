import Foundation
import Synchronization
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
    /// What the user picks in the desktop's dialog, which there's none of without it, as there's no note without
    /// `windowsNote`.
    var picked: Bitmap?
    var windowsNote: String?
    /// What each recording was asked to record.
    var recordings = Recordings()

    var name: String { "fake" }

    func recordingSource(area: CGRect, frameRate: Int, showsCursor: Bool) throws(ShotCommandError) -> any RecordingSource {
        if let reason = limits[.record] {
            throw .unavailable(reason)
        }
        recordings.asked.withLock { $0.append((area, frameRate, showsCursor)) }
        return GreyRecording()
    }

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

    func capturePicked() -> Bitmap? {
        picked
    }

    static func grey(_ points: CGRect) -> Bitmap {
        let width = Int(points.width * 2), height = Int(points.height * 2)
        return Bitmap(width: width, height: height, scale: 2, pixels: Data(repeating: 128, count: width * height * 4))!
    }
}

final class Recordings: Sendable {
    let asked = Mutex<[(area: CGRect, frameRate: Int, showsCursor: Bool)]>([])
}

/// Records a second of grey frames for each segment, written by ffmpeg when it finishes, however long it lasted, so the
/// answers don't depend on how promptly the tests' busy threads wake it.
private struct GreyRecording: RecordingSource {
    func start(to url: URL) async throws(ShotCommandError) -> any RecordingSegment {
        GreySegment(url: url)
    }
}

private struct GreySegment: RecordingSegment {
    let url: URL
    var offset: Double { 0 }

    func finish() async throws(ShotCommandError) -> Double? {
        do {
            _ = try await Subprocess.output(try FFmpegTools.find().ffmpeg, [
                "-v", "error", "-nostdin", "-f", "lavfi", "-i", "color=c=gray:s=64x48:r=30", "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                "-f", "mp4", "-y", url.path,
            ])
        } catch {
            throw .io("\(error)")
        }
        return 1
    }

    func cancel() {}
}

/// `shot serve` with `capturer` on a socket of its own, saving to a capture folder of its own, with settings that
/// `configure` can change, and a project store.
private final class Serve: @unchecked Sendable {
    let root: URL
    let folder: URL
    let socket: URL
    let projects: ProjectStore
    let marks: URL
    let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
    let server: AgentSocket.Server

    init(_ capturer: any ScreenCapturer = FakeScreen(), user: uid_t = getuid(), configure: (UserDefaults) -> Void = { _ in }) throws {
        root = try temporaryFolder()
        folder = root.appendingPathComponent("Shot", isDirectory: true)
        // A short folder of its own, since a socket's whole path must fit in 107 bytes.
        socket = URL(fileURLWithPath: "/tmp/ss-\(UUID().uuidString.prefix(8))/agent.sock")
        projects = ProjectStore(folder: root.appendingPathComponent("Projects", isDirectory: true))
        marks = root.appendingPathComponent("recording-marks.json")
        let store = try #require(UserDefaults(suiteName: suite))
        store.set(folder.path, forKey: PreferenceKey.saveFolder)
        store.set(true, forKey: PreferenceKey.saveAfterCapture)
        store.set(true, forKey: PreferenceKey.agentCapture)
        configure(store)
        store.synchronize()
        let suite = suite
        // Without registering defaults, which the whole process shares on Linux, so RegisteredDefaultsTests keeps them
        // to itself. The keys the daemon reads are set above, or fall back to the defaults.
        let daemon = AgentDaemon(capturer: capturer, projects: projects, marks: marks, version: "0.7.0", scratch: root.appendingPathComponent("segments")) {
            Preferences(store: UserDefaults(suiteName: suite)!)
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
    #expect(await serve.failure(AgentRequest(.pick)) == .notOnLinuxYet)
    #expect(await serve.failure(AgentRequest(.capture, target: AgentTarget(display: 2))) == .noInput("There's no display 2; this computer has 1. shot windows lists them."))
    #expect(await serve.failure(AgentRequest(.capture, target: AgentTarget(display: 1, rect: [300, 0, 10, 10]))) == .data("The rect 300,0,10,10 is off display 1, which is 200×100 points."))
    let missing = try #require(await serve.failure(AgentRequest(.capture, target: AgentTarget(window: "Calculator"))))
    #expect(missing.message.hasPrefix("No open window matches \"Calculator\". Open windows, front to back:\n  Terminal — ~\n  Firefox — Shot — docs"))
}

@Test func shotServeHasTheUserPickAWindowItCantFind() async throws {
    let picked = Bitmap(width: 30, height: 20, scale: 1, pixels: Data(repeating: 200, count: 30 * 20 * 4))!
    let serve = try Serve(FakeScreen(picked: picked, windowsNote: "Only some windows are listed."))
    let listed = try await serve.send(AgentRequest(.windows))
    #expect(listed["note"] == .string("Only some windows are listed."))

    // A window it lists is captured as before.
    #expect(try await serve.send(AgentRequest(.capture, target: AgentTarget(window: "Terminal")))["window"] == .object(["app": .string("Terminal"), "title": .string("~")]))
    let answer = try await serve.send(AgentRequest(.capture, target: AgentTarget(window: "Calculator", rect: [0, 0, 10, 50])))
    #expect(answer["window"] == .object(["picked": .bool(true)]))
    #expect(answer["note"] == .string(ScreenshotPortal.pickedNote))
    #expect(answer["size"] == .object(["width": .number(10), "height": .number(20)]))
    let file = URL(fileURLWithPath: try #require(answer["path"]?.string))
    #expect(PNGJPEGCodec().record(ofFileAt: file)?.source == CaptureRecord.Source(mode: "area"))
    #expect(await serve.failure(AgentRequest(.capture, target: AgentTarget(window: "Calculator", rect: [40, 0, 10, 10])))
        == .data("The rect 40,0,10,10 is off what was picked, which is 30×20 points."))
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
    // Wayland with no session bus to reach the portal on.
    let serve = try Serve(LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "wayland"]))
    #expect(await serve.failure(AgentRequest(.windows)) == .unavailable(ScreenshotPortal.noBus))
    #expect(await serve.failure(AgentRequest(.capture, target: AgentTarget(display: 1))) == .unavailable(ScreenshotPortal.noBus))
    let status = try await serve.send(AgentRequest(.status))
    #expect(status["capturer"] == .string("none"))
    #expect(status["limits"]?["captureWindow"] == .string(ScreenshotPortal.noBus))
    #expect(LinuxScreen.screenshotPortal(environment: ["XDG_SESSION_TYPE": "wayland"]) == .failure(.unavailable(ScreenshotPortal.noBus)))
    #expect(LinuxScreen.screenshotPortal(environment: ["XDG_SESSION_TYPE": "x11"]) == nil)
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

@Test func shotServeRecordsAWindowAndAnswersItsStopWithTheSavedVideoAndItsMarks() async throws {
    let screen = FakeScreen()
    let serve = try Serve(screen) { store in
        store.set(30, forKey: PreferenceKey.recordingFPS)
        store.set(true, forKey: PreferenceKey.recordShowsCursor)
    }
    var request = AgentRequest(.record, target: AgentTarget(window: "terminal"))
    request.origin = ProjectOrigin(via: .mcp, client: "test", action: AgentTools.recordWindow)
    let started = try await serve.send(request)
    let id = try #require(started["id"]?.string)
    #expect(started["window"] == .object(["app": .string("Terminal"), "title": .string("~")]))
    #expect(started["started"]?.string != nil)
    // The window as it is on screen, in points, at the frame rate Settings give, with the pointer as they say.
    #expect(screen.recordings.asked.withLock { $0.map(\.area) } == [CGRect(x: 10, y: 10, width: 60, height: 40)])
    #expect(screen.recordings.asked.withLock { $0.map(\.frameRate) } == [30])
    #expect(screen.recordings.asked.withLock { $0.map(\.showsCursor) } == [true])

    let status = try await serve.send(AgentRequest(.status))
    #expect(status["recording"]?["byAgent"] == .bool(true) && status["recording"]?["id"] == .string(id))
    #expect(status["recording"]?["window"] == started["window"])
    #expect(await serve.failure(AgentRequest(.record, target: AgentTarget(display: 1))) == .busy("Shot is already recording; try again once it's done."))
    // A capture can still be taken while it records.
    #expect(try await serve.send(AgentRequest(.capture, target: AgentTarget(display: 1)))["path"] != nil)

    try await Task.sleep(for: .milliseconds(600))
    let mark = try await serve.send(AgentRequest(.mark, id: id, label: "tapped Login"))
    #expect(mark["id"] == .string(id) && mark["label"] == .string("tapped Login"))
    let time = try #require(mark["time"]?.number)
    #expect(time >= 0.5)
    try await Task.sleep(for: .milliseconds(600))

    let stopped = try await serve.send(AgentRequest(.stop))
    #expect(stopped["id"] == .string(id))
    let path = try #require(stopped["path"]?.string)
    let video = URL(fileURLWithPath: path)
    #expect(video.deletingLastPathComponent().path == serve.folder.path)
    #expect(video.lastPathComponent.hasPrefix("Shot ") && video.pathExtension == "mp4")
    #expect(stopped["size"] == .object(["width": .number(64), "height": .number(48)]))
    #expect(stopped["duration"] == .number(1))
    #expect(stopped["marks"] == .array([.object(["time": .number(time), "label": .string("tapped Login")])]))
    #expect(RecordingMarks.marks(for: video, in: serve.marks) == [RecordingMark(time: time, label: "tapped Login")])
    let entry = try #require(serve.projects.entry(for: video))
    #expect(entry.origin.via == .mcp && entry.origin.client == "test" && entry.origin.action == AgentTools.recordWindow)

    // Once it's over, a stop by its ID answers the same, a mark is refused, and nothing records.
    #expect(try await serve.send(AgentRequest(.stop, id: id)) == stopped)
    #expect(await serve.failure(AgentRequest(.mark, id: id, label: "late")) == .noInput("The agent recording \(id) has ended, so it can't be marked."))
    #expect(await serve.failure(AgentRequest(.mark, label: "late")) == .noInput("No agent recording is in progress to mark."))
    #expect(await serve.failure(AgentRequest(.stop)) == .noInput("No agent recording is in progress. To get one that has already ended, stop it by the id it started with."))
    #expect(await serve.failure(AgentRequest(.stop, id: "nope")) == .noInput("No agent recording has the id nope. Finished ones are kept for 10 minutes."))
    #expect(try await serve.send(AgentRequest(.status))["recording"] == .null)
}

@Test func shotServeAnswersATimedRecordingOnceItsSaved() async throws {
    let serve = try Serve()
    let answer = try await serve.send(AgentRequest(.record, target: AgentTarget(display: 1, rect: [150, 80, 100, 100]), duration: 1))
    #expect(answer["duration"] == .number(1))
    #expect(answer["marks"] == nil && answer["path"]?.string?.hasSuffix(".mp4") == true)
    #expect(try await serve.send(AgentRequest(.status))["recording"] == .null)
}

@Test func shotServeRefusesARecordingItCantMake() async throws {
    let wayland = try Serve(FakeScreen(limits: [.record: ScreenshotPortal.noRecording]))
    #expect(await wayland.failure(AgentRequest(.record, target: AgentTarget(display: 1))) == .unavailable(ScreenshotPortal.noRecording))
    let serve = try Serve()
    #expect(await serve.failure(AgentRequest(.record, target: AgentTarget(display: 2))) == .noInput("There's no display 2; this computer has 1. shot windows lists them."))
    #expect(await serve.failure(AgentRequest(.record, target: AgentTarget(window: "Terminal", rect: [100, 0, 10, 10]))) == .data("The rect 100,0,10,10 is off Terminal — ~, which is 60×40 points."))
    let missing = try #require(await serve.failure(AgentRequest(.record, target: AgentTarget(window: "Calculator"))))
    #expect(missing.message.hasPrefix("No open window matches \"Calculator\"."))
    #expect(!FileManager.default.fileExists(atPath: serve.folder.path))
}
