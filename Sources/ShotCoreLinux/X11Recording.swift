import Foundation

/// Records part of an X server's screen with ffmpeg's `x11grab`, one ffmpeg a segment, as `FFmpeg.grabArguments`
/// plans. A window is recorded as the rectangle it had when the recording started, with whatever covers it.
struct X11Recording: RecordingSource {
    /// The X server, as `DISPLAY` names it.
    let display: String
    /// In the root window's pixels, with an even width and height.
    let area: CGRect
    let frameRate: Int
    let showsCursor: Bool

    /// How long ffmpeg may take to start grabbing, or to finish writing once it's asked to stop.
    static let patience = Duration.seconds(20)

    func start(to url: URL) async throws(ShotCommandError) -> any RecordingSegment {
        let tools = try FFmpegTools.find()
        // A segment stops by itself a little after the longest recording, so one whose `shot serve` was killed ends too.
        let arguments = FFmpeg.grabArguments(
            display: display, area: area, frameRate: frameRate, showsCursor: showsCursor, limit: AgentRequest.maximumDuration + 10, output: url.path
        )
        let process: Subprocess
        do {
            process = try Subprocess(tools.ffmpeg, arguments, writable: true)
        } catch {
            throw .io("Couldn't start ffmpeg to record the screen: \(error.localizedDescription)")
        }
        let watchdog = Task {
            if (try? await Task.sleep(for: Self.patience)) != nil {
                process.stop()
            }
        }
        defer { watchdog.cancel() }
        // Its first report with a time comes once it has recorded a frame, or it stops first and says why. A byte at a
        // time, since a read waits for as many bytes as it asks for.
        var progress = FFmpeg.Progress()
        while !progress.hasStarted {
            let byte = await process.read(upTo: 1)
            guard !byte.isEmpty else {
                do {
                    try await process.wait()
                } catch {
                    throw .io("ffmpeg couldn't record the screen: \(error.localizedDescription)")
                }
                throw .io("ffmpeg stopped before it recorded anything.")
            }
            progress.read(byte)
        }
        return X11Segment(process: process, progress: progress)
    }
}

/// One ffmpeg grabbing the screen, whose progress reports are read as they come, so it never waits to write them, and
/// say how much it recorded.
final class X11Segment: RecordingSegment {
    let process: Subprocess
    let offset: Double
    private let reports: Task<FFmpeg.Progress, Never>

    init(process: Subprocess, progress: FFmpeg.Progress) {
        self.process = process
        offset = progress.recorded ?? 0
        reports = Task {
            var progress = progress
            while true {
                let chunk = await process.read(upTo: 4096)
                guard !chunk.isEmpty else {
                    return progress
                }
                progress.read(chunk)
            }
        }
    }

    func finish() async throws(ShotCommandError) -> Double? {
        // `q` has it finish the file, where killing it would leave the file without its index. It may have stopped already.
        _ = await process.write(FFmpeg.stopKey)
        await process.closeInput()
        let process = process
        let watchdog = Task {
            if (try? await Task.sleep(for: X11Recording.patience)) != nil {
                process.stop()
            }
        }
        defer { watchdog.cancel() }
        let progress = await reports.value
        do {
            try await process.wait()
        } catch {
            throw .io("ffmpeg stopped recording the screen: \(error.localizedDescription)")
        }
        return progress.recorded
    }

    func cancel() {
        process.stop()
    }
}
