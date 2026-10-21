import Foundation
import Testing
@testable import ShotCore
@testable import ShotCoreLinux

/// PipeWire and WirePlumber of their own, in a runtime folder nothing else uses, with GStreamer's `pipewiresink`
/// providing a still 320×240 video source of `color`, as a screen cast's node would be. Stopped when it's released.
final class TestPipeWire: @unchecked Sendable {
    static let pipewire = TestServer.executable("/usr/bin/pipewire")
    static let wireplumber = TestServer.executable("/usr/bin/wireplumber")
    static let gstreamer = TestServer.executable("/usr/bin/gst-launch-1.0")
    static let dump = TestServer.executable("/usr/bin/pw-dump")
    static var isInstalled: Bool { [pipewire, wireplumber, gstreamer, dump].allSatisfy { $0 != nil } }

    /// Red, green and blue.
    static let color: (r: UInt8, g: UInt8, b: UInt8) = (0x33, 0x99, 0xCC)

    let runtime: URL
    /// The source's node.
    private(set) var node: UInt32 = 0
    private var pids: [pid_t] = []

    init(bus: TestBus) async throws {
        // A short folder of its own, since a socket's whole path must fit in 107 bytes.
        runtime = URL(fileURLWithPath: "/tmp/pw-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let environment = ["XDG_RUNTIME_DIR": runtime.path, "PIPEWIRE_RUNTIME_DIR": runtime.path, "DBUS_SESSION_BUS_ADDRESS": bus.address]
        do {
            pids.append(try TestServer.spawn(try #require(Self.pipewire), [], environment: environment))
            try await wait("PipeWire didn't start.") { FileManager.default.fileExists(atPath: self.runtime.appendingPathComponent("pipewire-0").path) }
            pids.append(try TestServer.spawn(try #require(Self.wireplumber), [], environment: environment))
            let foreground = String(format: "0xff%02x%02x%02x", Self.color.r, Self.color.g, Self.color.b)
            pids.append(try TestServer.spawn(try #require(Self.gstreamer), [
                "-q", "videotestsrc", "is-live=true", "pattern=solid-color", "foreground-color=\(foreground)", "!",
                "video/x-raw,format=BGRx,width=320,height=240,framerate=30/1", "!",
                "pipewiresink", "mode=provide", "stream-properties=\"props,media.class=Video/Source,node.name=shot-test\"",
            ], environment: environment))
            var found: UInt32?
            try await wait("GStreamer's source didn't show up in PipeWire.") {
                found = await self.sourceNode()
                return found != nil
            }
            node = try #require(found)
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
    }

    private func stop() {
        for pid in pids.reversed() {
            TestServer.stop(pid)
        }
        pids = []
        try? FileManager.default.removeItem(at: runtime)
    }

    /// Waits up to 10 seconds for `ready`.
    private func wait(_ failure: String, _ ready: () async -> Bool) async throws {
        for _ in 0 ..< 200 {
            if await ready() {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ShotCommandError.internal(failure)
    }

    /// The node GStreamer's source has, from what `pw-dump` lists.
    private func sourceNode() async -> UInt32? {
        guard let dump = Self.dump,
              let output = try? await Subprocess.output("/usr/bin/env", ["XDG_RUNTIME_DIR=\(runtime.path)", "PIPEWIRE_RUNTIME_DIR=\(runtime.path)", dump]),
              let objects = try? JSONSerialization.jsonObject(with: output) as? [[String: Any]]
        else {
            return nil
        }
        for object in objects {
            if let info = object["info"] as? [String: Any], let props = info["props"] as? [String: Any], props["node.name"] as? String == "shot-test",
               let id = object["id"] as? Int {
                return UInt32(id)
            }
        }
        return nil
    }
}

/// CI installs PipeWire, WirePlumber and GStreamer, so there a missing one fails rather than skips.
private let hasPipeWire = (TestPipeWire.isInstalled && TestBus.executable != nil) || ProcessInfo.processInfo.environment["CI"] != nil

/// One at a time, since each records for seconds on CI's few cores.
@Suite(.serialized, .enabled(if: hasPipeWire, "PipeWire, WirePlumber or GStreamer isn't installed")) struct ScreenCastRecordingTests {
    @Test func screenCastRecordingPausesResumesAndJoinsTheSegments() async throws {
        try await HeavyTests.oneAtATime {
            let bus = try await TestBus()
            let pipewire = try await TestPipeWire(bus: bus)
            let portal = try FakePortal(on: bus.address, FakePortal.Options(screenCast: (pipewire.node, pipewire.runtime)))
            defer { portal.stop() }
            let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
            defer {
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: LinuxSettings.file(suite: suite))
            }
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let capturer = try PortalCapturer(address: bus.address, settings: suite)
            #expect(capturer.limits.isEmpty)
            #expect(LinuxScreen.screenCastPortal(environment: ["XDG_SESSION_TYPE": "wayland", "DBUS_SESSION_BUS_ADDRESS": bus.address])?.version == .success(5))
            let display = try #require(try await capturer.displays().first)
            let source = try capturer.recordingSource(area: display.frame, frameRate: 30, showsCursor: false)

            let started = ContinuousClock.now
            let recorder = try await SegmentRecorder(source: source, assembler: FFmpegAssembler(), scratch: folder)
            try await Task.sleep(for: .milliseconds(1500))
            await recorder.pause()
            let paused = ContinuousClock.now
            // Long enough that a pause counted would show past the slack below.
            try await Task.sleep(for: .milliseconds(1500))
            let resuming = ContinuousClock.now
            try await recorder.resume()
            try await Task.sleep(for: .milliseconds(1500))
            let output = folder.appendingPathComponent("recording.mp4")
            let elapsed = try await recorder.stop(to: output)
            let wall = (ContinuousClock.now - started) - (resuming - paused)

            // The pause is left out of the 3 seconds or more recorded, and the time it gives is how long the file is, to a
            // frame or two.
            #expect(elapsed >= 2.9 && .seconds(elapsed) < wall + .milliseconds(300), "\(elapsed) s against \(wall) recording")
            let probe = try await FFmpegTools.find().probe(output)
            #expect(abs(probe.duration - elapsed) < 0.1, "\(probe.duration) against \(elapsed)")
            // An average, which the last frame's length can move a little off 30.
            #expect(probe.frameRate.map { $0.rounded() } == 30, "\(String(describing: probe.frameRate))")
            // The whole stream, in its pixels.
            #expect(probe.size == CGSize(width: 320, height: 240))
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["recording.mp4"])

            let shown = try await frames(of: output, at: [0.5, 2.5])
            for frame in shown {
                let image = try #require(try? frame.decoded.get().image)
                let middle = color(image, x: 0.5, y: 0.5)
                #expect(abs(Int(middle.r) - Int(TestPipeWire.color.r)) <= 6 && abs(Int(middle.g) - Int(TestPipeWire.color.g)) <= 6
                    && abs(Int(middle.b) - Int(TestPipeWire.color.b)) <= 6, "\(middle)")
            }

            // One screen cast for both segments, asked for once, without the pointer, its permission kept, and closed once
            // it's over, its token kept for the next.
            #expect(portal.selected.withLock { $0 } == [["types": .uint32(1), "multiple": .bool(false), "cursor_mode": .uint32(1), "persist_mode": .uint32(2)]])
            #expect(portal.closed.withLock { $0.count } == 1)
            #expect(UserDefaults(suiteName: suite)?.string(forKey: ScreenCastPortal.tokenKey) == "token-1")
        }
    }

    @Test func shotServeRecordsAWaylandScreenRestoresItAndHasTheUserPickAWindow() async throws {
        try await HeavyTests.oneAtATime {
            let bus = try await TestBus()
            let pipewire = try await TestPipeWire(bus: bus)
            // The screenshot that sizes the display is as big as the screen cast's monitor, in points.
            var options = FakePortal.Options(screenCast: (pipewire.node, pipewire.runtime))
            options.image = try #require(Bitmap(width: 160, height: 120, scale: 1, pixels: FakePortal.pattern(width: 160, height: 120)))
            let portal = try FakePortal(on: bus.address, options)
            defer { portal.stop() }
            let root = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: root) }
            let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
            let store = try #require(UserDefaults(suiteName: suite))
            store.set(root.appendingPathComponent("Shot").path, forKey: PreferenceKey.saveFolder)
            store.set(true, forKey: PreferenceKey.saveAfterCapture)
            store.set(true, forKey: PreferenceKey.agentCapture)
            store.set(30, forKey: PreferenceKey.recordingFPS)
            store.set(true, forKey: PreferenceKey.recordShowsCursor)
            defer {
                store.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: LinuxSettings.file(suite: suite))
            }
            let capturer = LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "wayland", "DBUS_SESSION_BUS_ADDRESS": bus.address], settings: suite)
            #expect(capturer.name == "portal" && capturer.limits.isEmpty)
            let daemon = AgentDaemon(capturer: capturer, projects: nil, version: "0.7.0", scratch: root.appendingPathComponent("segments")) {
                Preferences(store: UserDefaults(suiteName: suite)!)
            }

            // Part of the screen, which is 160×120 points of 320×240 pixels.
            let part = try await daemon.handle(AgentRequest(.record, target: AgentTarget(display: 1, rect: [40, 30, 80, 60]), duration: 1)).get()
            #expect(part["size"] == .object(["width": .number(160), "height": .number(120)]))
            #expect(part["note"] == nil)
            // The next restores the screen with the token the first was given, and a stored token the portal turns down is
            // forgotten, and the user asked again.
            _ = try await daemon.handle(AgentRequest(.record, target: AgentTarget(display: 1), duration: 1)).get()
            store.set("malformed", forKey: ScreenCastPortal.tokenKey)
            let whole = try await daemon.handle(AgentRequest(.record, target: AgentTarget(display: 1), duration: 1)).get()
            #expect(whole["size"] == .object(["width": .number(320), "height": .number(240)]))
            #expect(portal.selected.withLock { $0.map { $0["restore_token"] } } == [nil, .string("token-1"), .string("malformed"), nil])
            #expect(portal.selected.withLock { $0.allSatisfy { $0["cursor_mode"] == .uint32(2) } })
            #expect(UserDefaults(suiteName: suite)?.string(forKey: ScreenCastPortal.tokenKey)?.hasPrefix("token-") == true)

            // A window is picked in the desktop's dialog, without a token, and the answers say so.
            let started = try await daemon.handle(AgentRequest(.record, target: AgentTarget(window: "Terminal"))).get()
            #expect(started["window"] == .object(["picked": .bool(true)]) && started["note"] == .string(ScreenCastPortal.pickedNote))
            let id = try #require(started["id"]?.string)
            try await Task.sleep(for: .seconds(1))
            let stopped = try await daemon.handle(AgentRequest(.stop, id: id)).get()
            #expect(stopped["note"] == .string(ScreenCastPortal.pickedNote))
            #expect(portal.selected.withLock { $0.last } == ["types": .uint32(2), "multiple": .bool(false), "cursor_mode": .uint32(2)])
            #expect(portal.closed.withLock { $0.count } == 5)
        }
    }

    @Test func screenCastRecordingSaysWhenTheUserCancels() async throws {
        try await HeavyTests.oneAtATime {
            let bus = try await TestBus()
            let portal = try FakePortal(on: bus.address, FakePortal.Options(screenCast: (1, URL(fileURLWithPath: "/nonexistent")), castResponse: 1))
            defer { portal.stop() }
            let folder = try temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let capturer = try PortalCapturer(address: bus.address)
            let source = try #require(try capturer.pickedRecordingSource(rect: nil, frameRate: 30, showsCursor: false))
            await #expect(throws: ShotCommandError.noInput("The recording was cancelled or not allowed in the desktop's dialog, so nothing was recorded.")) {
                _ = try await SegmentRecorder(source: source, assembler: FFmpegAssembler(), scratch: folder)
            }
            #expect(portal.closed.withLock { $0.count } == 1)
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
    }
}
