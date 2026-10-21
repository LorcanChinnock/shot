import CXCB
import Foundation
import Testing
@testable import ShotCore
@testable import ShotCoreLinux

/// A black screen with a still blue window, and a red one that slides along the top while `moving` runs, all in its top
/// left 320×240, which is what's recorded, so the tests cost CI's few cores little beside the perf budgets.
private struct MovingScene {
    let server: XServer
    let desktop: Desktop
    let red, blue: xcb_window_t

    init() async throws {
        server = try await XServer()
        desktop = try Desktop(server)
        blue = desktop.window(CGRect(x: 200, y: 150, width: 100, height: 80), color: 0x0000FF, title: "Still blue", windowClass: "blue\0Blue\0")
        red = desktop.window(CGRect(x: 0, y: 20, width: 60, height: 60), color: 0xFF0000, title: "Moving red", windowClass: "red\0Red\0")
        desktop.listClients([red, blue])
        desktop.sync()
    }

    /// Slides the red window 4 pixels every 40 ms until the task is cancelled.
    func moving() -> Task<Void, Never> {
        let (desktop, red) = (desktop, red)
        return Task {
            var x = 0
            while !Task.isCancelled {
                x = (x + 4) % 260
                desktop.move(red, to: CGPoint(x: x, y: 20))
                desktop.sync()
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }
}

/// One at a time, since each records for seconds on CI's few cores.
@Suite(.serialized, .enabled(if: hasXvfb, "Xvfb isn't installed")) struct X11RecordingTests {
    @Test func x11RecordingPausesResumesAndJoinsTheSegments() async throws {
        let scene = try await MovingScene()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let capturer = try X11Capturer(display: scene.server.display)
        let source = try capturer.recordingSource(area: CGRect(x: 0, y: 0, width: 320, height: 240), frameRate: 30, showsCursor: false)
        let moving = scene.moving()
        defer { moving.cancel() }

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

        // The pause is left out of the 3 seconds or more recorded, which each segment starts a little before it says it
        // has, and ends a little after it's asked to. The time it gives is how long the file is, to a frame or two.
        #expect(elapsed >= 2.9 && .seconds(elapsed) < wall + .milliseconds(300), "\(elapsed) s against \(wall) recording")
        let probe = try await FFmpegTools.find().probe(output)
        #expect(abs(probe.duration - elapsed) < 0.1, "\(probe.duration) against \(elapsed)")
        // An average, which the last frame's length can move a little off 30.
        #expect(probe.frameRate.map { $0.rounded() } == 30, "\(String(describing: probe.frameRate))")
        #expect(probe.size == CGSize(width: 320, height: 240))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["recording.mp4"])

        let shown = try await frames(of: output, at: [0.5, 2.5])
        let early = try #require(try? shown[0].decoded.get().image), late = try #require(try? shown[1].decoded.get().image)
        for frame in [early, late] {
            let blue = color(frame, x: 250 / 320, y: 190 / 240), black = color(frame, x: 160 / 320, y: 200 / 240)
            #expect(blue.r < 20 && blue.g < 20 && blue.b > 230, "\(blue)")
            #expect(black.r < 20 && black.g < 20 && black.b < 20, "\(black)")
        }
        // The red window moved between them.
        let redColumns = { (frame: PlatformImage) in
            (0 ..< 64).filter { column in color(frame, x: (Double(column) * 5 + 2) / 320, y: 50 / 240).r > 200 }
        }
        #expect(!redColumns(early).isEmpty && !redColumns(late).isEmpty)
        #expect(redColumns(early) != redColumns(late))
    }

    @Test func shotServeRecordsAnX11WindowAndItsMarkReachesGetFrames() async throws {
        let scene = try await MovingScene()
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Shot", isDirectory: true)
        let marks = root.appendingPathComponent("recording-marks.json")
        let suite = "dev.lorcan.Shot.tests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.set(folder.path, forKey: PreferenceKey.saveFolder)
        store.set(true, forKey: PreferenceKey.saveAfterCapture)
        store.set(true, forKey: PreferenceKey.agentCapture)
        store.set(30, forKey: PreferenceKey.recordingFPS)
        defer {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: LinuxSettings.file(suite: suite))
        }
        let capturer = LinuxScreen.capturer(environment: ["XDG_SESSION_TYPE": "x11", "DISPLAY": scene.server.display])
        let daemon = AgentDaemon(capturer: capturer, projects: nil, marks: marks, version: "0.7.0", scratch: root.appendingPathComponent("segments")) {
            Preferences(store: UserDefaults(suiteName: suite)!)
        }
        let moving = scene.moving()
        defer { moving.cancel() }

        let started = try await daemon.handle(AgentRequest(.record, target: AgentTarget(window: "still blue"))).get()
        #expect(started["window"] == .object(["app": .string("Blue"), "title": .string("Still blue")]))
        let id = try #require(started["id"]?.string)
        try await Task.sleep(for: .seconds(1))
        let mark = try await daemon.handle(AgentRequest(.mark, id: id, label: "tapped Login")).get()
        try await Task.sleep(for: .seconds(1))
        let stopped = try await daemon.handle(AgentRequest(.stop, id: id)).get()
        // The blue window alone, at its size.
        #expect(stopped["size"] == .object(["width": .number(100), "height": .number(80)]))
        let duration = try #require(stopped["duration"]?.number)
        #expect(duration >= 1.5, "\(duration)")
        let path = try #require(stopped["path"]?.string)
        let time = try #require(mark["time"]?.number)
        #expect(RecordingMarks.marks(for: URL(fileURLWithPath: path), in: marks) == [RecordingMark(time: time, label: "tapped Login")])

        let tools = AgentTools.live(folder: folder, marks: marks)
        let result = await tools.call(AgentTools.getFrames, .object(["path": .string(path), "count": .number(2)]))
        let text = result.content.compactMap { if case let .text(text) = $0 { text } else { nil } }.joined(separator: "\n")
        #expect(result.isError != true, "\(text)")
        #expect(text.contains("tapped Login"), "\(text)")
    }
}
