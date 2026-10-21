import Foundation

/// Where a recording's frames come from where Shot has no app to record: `shot serve` on Linux gets one from its
/// `ScreenCapturer`, such as X11's, which has ffmpeg grab the screen. The Mac app records on its own and doesn't use it.
public protocol RecordingSource: Sendable {
    /// Starts writing frames to `url`, as MP4, and returns once they're being written. Throws why it can't.
    func start(to url: URL) async throws(ShotCommandError) -> any RecordingSegment
    /// Lets go of what it keeps between segments, such as a screen cast, once the recording has stopped or been thrown
    /// away.
    func end() async
}

extension RecordingSource {
    public func end() async {}
}

/// One stretch of a recording, from a start or resume to a pause or stop.
public protocol RecordingSegment: Sendable {
    /// How many seconds it had recorded by the time it started, which a source that hears late may have.
    var offset: Double { get }
    /// Stops taking frames and returns once the file is whole, with how many seconds it holds when that's known, since
    /// it may take frames for a moment after it's asked to stop. Throws when it failed, such as when the screen went away
    /// while it recorded.
    func finish() async throws(ShotCommandError) -> Double?
    /// Stops at once, leaving the file unfinished, for a recording that's being thrown away.
    func cancel()
}

/// Records from a `RecordingSource` one segment at a time, as the Mac's `Recorder` does: each pause ends a segment and
/// each resume starts one, and a stop joins them through `assembler` into one MP4. The segments are kept in a folder of
/// their own under `scratch` until then.
public actor SegmentRecorder {
    public enum Phase: Equatable, Sendable {
        case recording
        case paused
        /// Stopped or thrown away, so it records nothing more.
        case ended
    }

    let source: any RecordingSource
    let assembler: any VideoAssembler
    let folder: URL
    /// Seconds on a clock that only goes forward.
    let now: @Sendable () -> Double
    public private(set) var phase: Phase = .recording
    private var clock: RecordingClock
    private var segments: [URL] = []
    private var segment: (any RecordingSegment)?
    private var locked = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// Why a segment failed, which the stop throws.
    private var failure: ShotCommandError?

    /// Starts recording from `source`, and returns once the first segment is being written.
    public init(
        source: any RecordingSource, assembler: any VideoAssembler, scratch: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Shot/segments"),
        now: @escaping @Sendable () -> Double = SegmentRecorder.uptime
    ) async throws(ShotCommandError) {
        self.source = source
        self.assembler = assembler
        folder = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.now = now
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw .cantCreate("Couldn't make a folder for the recording in \(scratch.path): \(error.localizedDescription)")
        }
        let url = folder.appendingPathComponent("0.mp4")
        let first: any RecordingSegment
        do {
            first = try await source.start(to: url)
        } catch {
            await source.end()
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        segment = first
        segments = [url]
        clock = RecordingClock(start: now(), offset: first.offset)
    }

    /// The seconds since `ProcessInfo`'s uptime started, which only go forward.
    public static let uptime: @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }

    /// How far into the saved video it is now, pauses left out.
    public var elapsed: Double {
        clock.elapsed(at: now())
    }

    /// Ends the segment under way, so nothing more is recorded until `resume`.
    public func pause() async {
        await lock()
        defer { unlock() }
        guard phase == .recording else {
            return
        }
        phase = .paused
        let paused = now()
        do {
            clock.pause(at: paused, length: try await segment?.finish())
        } catch {
            clock.pause(at: paused)
            failure = failure ?? error
        }
        segment = nil
    }

    /// Starts a new segment after a pause. Throws why it couldn't, and stays paused then.
    public func resume() async throws(ShotCommandError) {
        await lock()
        defer { unlock() }
        guard phase == .paused else {
            return
        }
        let url = folder.appendingPathComponent("\(segments.count).mp4")
        let started = try await source.start(to: url)
        segment = started
        segments.append(url)
        phase = .recording
        clock.resume(at: now(), offset: started.offset)
    }

    /// Stops recording and joins the segments at `output`, which is replaced, returning how long the recording is, pauses
    /// left out. The segments are removed either way.
    public func stop(to output: URL) async throws(ShotCommandError) -> Double {
        await lock()
        defer { unlock() }
        guard phase != .ended else {
            throw .internal("the recording has already stopped")
        }
        phase = .ended
        let stopped = now()
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            clock.pause(at: stopped, length: try await segment?.finish())
        } catch {
            failure = failure ?? error
        }
        segment = nil
        await source.end()
        if let failure {
            throw failure
        }
        do {
            try await VideoConcatenator.concatenate(segments, to: output, assembler: assembler)
        } catch let error as ShotCommandError {
            throw error
        } catch {
            throw .io("Couldn't join the recording: \(error.localizedDescription)")
        }
        return clock.elapsed(at: stopped)
    }

    /// Stops recording and throws the segments away.
    public func discard() async {
        await lock()
        defer { unlock() }
        phase = .ended
        segment?.cancel()
        segment = nil
        await source.end()
        try? FileManager.default.removeItem(at: folder)
    }

    /// Waits for the pause, resume or stop under way, since each waits for ffmpeg, so they never overlap.
    private func lock() async {
        guard locked else {
            locked = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Lets the next one waiting go, which holds the lock from here.
    private func unlock() {
        if waiting.isEmpty {
            locked = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
