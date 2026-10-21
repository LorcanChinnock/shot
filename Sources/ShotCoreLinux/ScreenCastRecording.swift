import Foundation
import Synchronization

/// Records a Wayland screen, or a window the user picks, through the desktop portal's ScreenCast interface: the first
/// segment opens a screen cast, which lasts until the recording ends, and reads its PipeWire stream, and each segment
/// has an ffmpeg encode the newest frame at the frame rate, as `FFmpeg.castArguments` plans. Frames keep the first
/// frame's size, as `CastFrame` packs them.
final class ScreenCastRecording: RecordingSource {
    let portal: PortalCapturer
    /// Whether the user picks a window, rather than a screen, which a stored token may pick again without asking.
    let window: Bool
    /// The part to record, in points on the desktop for a screen, or from the picked window's top-left; all of it
    /// when `nil`.
    let area: CGRect?
    let frameRate: Int
    let showsCursor: Bool

    /// How long the stream may take to send its first frame, and ffmpeg to start or finish.
    static let patience = Duration.seconds(20)

    private struct State {
        var cast: PortalCapturer.ScreenCast?
        var stream: PipeWireStream?
        var ticker: Task<Void, Never>?
        /// The first frame's size, and layout, which every frame is packed into.
        var size: (width: Int, height: Int)?
        var format = 0
        /// The newest frame, packed.
        var latest: Data?
        /// Why the stream ended, once it has.
        var ended: String?
        /// Those waiting for the first frame.
        var waiting: [CheckedContinuation<Result<Void, ShotCommandError>, Never>] = []
        /// The ffmpeg of the segment under way, and whether a frame is being written to it.
        var sink: Subprocess?
        var writing = false
    }

    private let state = Mutex(State())

    init(portal: PortalCapturer, window: Bool, area: CGRect?, frameRate: Int, showsCursor: Bool) {
        self.portal = portal
        self.window = window
        self.area = area
        self.frameRate = frameRate
        self.showsCursor = showsCursor
    }

    func start(to url: URL) async throws(ShotCommandError) -> any RecordingSegment {
        let cast = try await open()
        let (size, format) = state.withLock { ($0.size ?? (0, 0), $0.format) }
        let frame = CGSize(width: size.width, height: size.height)
        guard let crop = ScreenCastPortal.crop(area, onDesktop: !window, stream: cast.started.stream, frame: frame) else {
            let shown = area.map { "The area at \(Int($0.minX)),\(Int($0.minY)), \(Int($0.width))×\(Int($0.height)) points," } ?? "The screen cast"
            throw .data("\(shown) is off what's being recorded, which is \(size.width)×\(size.height) pixels.")
        }
        let tools = try FFmpegTools.find()
        // A segment stops by itself a little after the longest recording, so one whose `shot serve` was killed ends too.
        let arguments = FFmpeg.castArguments(
            size: frame, pixelFormat: FFmpeg.castPixelFormats[format], crop: crop == CGRect(origin: .zero, size: frame) ? nil : crop, frameRate: frameRate,
            limit: AgentRequest.maximumDuration + 10, output: url.path, version: await tools.version()
        )
        let process: Subprocess
        do {
            process = try Subprocess(tools.ffmpeg, arguments, writable: true)
        } catch {
            throw .io("Couldn't start ffmpeg to record the screen: \(error.localizedDescription)")
        }
        state.withLock { $0.sink = process }
        let detach = { @Sendable [weak self] in
            self?.state.withLock { state in
                if state.sink === process {
                    state.sink = nil
                }
            }
        }
        do {
            // Closing its input has it finish the file, once the frame being written has gone.
            return try await FFmpegSegment.started(process, patience: Self.patience) {
                detach()
                await process.closeInput()
            }
        } catch {
            detach()
            throw error
        }
    }

    func end() async {
        let (cast, stream, ticker, waiting) = state.withLock { state in
            defer {
                state = State()
            }
            return (state.cast, state.stream, state.ticker, state.waiting)
        }
        ticker?.cancel()
        stream?.stop()
        if let cast {
            portal.close(cast)
        }
        for waiter in waiting {
            waiter.resume(returning: .failure(.io("The recording stopped before the screen cast sent anything.")))
        }
    }

    /// The screen cast, opened the first time, once its stream has sent a frame, which sets the recording's size.
    private func open() async throws(ShotCommandError) -> PortalCapturer.ScreenCast {
        if let cast = state.withLock({ $0.stream == nil ? nil : $0.cast }) {
            return cast
        }
        let cast = try await portal.screenCast(window: window, showsCursor: showsCursor)
        state.withLock { $0.cast = cast }
        let stream: PipeWireStream
        do {
            stream = try PipeWireStream(fd: cast.fd, node: cast.started.stream.node, frameRate: frameRate, frame: { [weak self] pixels, width, height, stride, format in
                self?.received(pixels, width: width, height: height, stride: stride, format: format)
            }, ended: { [weak self] reason in
                self?.ended(reason)
            })
        } catch {
            await end()
            throw error
        }
        state.withLock { $0.stream = stream }
        let timeout = Task { [weak self] in
            if (try? await Task.sleep(for: Self.patience)) != nil {
                self?.settle(.failure(.unavailable("The screen cast sent nothing to record within \(Self.patience.components.seconds) seconds.")))
            }
        }
        defer { timeout.cancel() }
        let first = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, ShotCommandError>, Never>) in
            let ready = state.withLock { state -> Result<Void, ShotCommandError>? in
                if state.latest != nil {
                    return .success(())
                }
                if let reason = state.ended {
                    return .failure(Self.failure(reason))
                }
                state.waiting.append(continuation)
                return nil
            }
            if let ready {
                continuation.resume(returning: ready)
            }
        }
        do {
            try first.get()
        } catch {
            await end()
            throw error
        }
        startTicking()
        return cast
    }

    /// Packs a frame from the stream's thread and keeps it as the newest.
    private func received(_ pixels: UnsafeRawPointer, width: Int, height: Int, stride: Int, format: Int) {
        let (size, first) = state.withLock { state in
            if state.size == nil {
                state.size = (width, height)
                state.format = format
            }
            return (state.size!, state.format)
        }
        let packed = CastFrame.packed(
            pixels, width: width, height: height, stride: stride, into: size, swapsRedAndBlue: CastFrame.isRedFirst(format) != CastFrame.isRedFirst(first)
        )
        let isFirst = state.withLock { state in
            defer { state.latest = packed }
            return state.latest == nil
        }
        if isFirst {
            settle(.success(()))
        }
    }

    private func ended(_ reason: String) {
        state.withLock { $0.ended = reason }
        settle(.failure(Self.failure(reason)))
    }

    private static func failure(_ reason: String) -> ShotCommandError {
        .io("The screen cast stopped before it sent anything to record: \(reason).")
    }

    /// Answers those waiting for the first frame.
    private func settle(_ result: Result<Void, ShotCommandError>) {
        let waiting = state.withLock { state in
            defer { state.waiting = [] }
            return state.waiting
        }
        for waiter in waiting {
            waiter.resume(returning: result)
        }
    }

    /// Writes the newest frame to the segment under way at the frame rate, so a screen that doesn't change, which the
    /// stream sends no frames for, still fills its time, skipping a tick while ffmpeg is still reading the last one.
    /// The ffmpeg stamps each frame as it comes, so the timing needn't be exact.
    private func startTicking() {
        let interval = Duration.seconds(1) / max(1, frameRate)
        let ticker = Task.detached { [weak self] in
            var next = ContinuousClock.now
            while !Task.isCancelled {
                self?.tick()
                next += interval
                // One that has fallen behind skips the ticks it missed.
                if next < .now {
                    next = .now
                }
                try? await Task.sleep(until: next, clock: .continuous)
            }
        }
        state.withLock { $0.ticker = ticker }
    }

    private func tick() {
        let next = state.withLock { state -> (Subprocess, Data)? in
            guard let sink = state.sink, !state.writing, let latest = state.latest else {
                return nil
            }
            state.writing = true
            return (sink, latest)
        }
        guard let (sink, frame) = next else {
            return
        }
        Task { [weak self] in
            _ = await sink.write(frame)
            self?.state.withLock { $0.writing = false }
        }
    }
}
