import Foundation

/// One ffmpeg recording a segment, whose `-progress` reports, as `FFmpeg.grabArguments` asks for them, are read as they
/// come, so it never waits to write them, and say how much it recorded. `X11Recording` and `ScreenCastRecording` stop it
/// in their own ways.
final class FFmpegSegment: RecordingSegment {
    let process: Subprocess
    let offset: Double
    private let reports: Task<FFmpeg.Progress, Never>
    private let stop: @Sendable () async -> Void
    private let patience: Duration

    private init(process: Subprocess, progress: FFmpeg.Progress, patience: Duration, stop: @escaping @Sendable () async -> Void) {
        self.process = process
        offset = progress.recorded ?? 0
        self.stop = stop
        self.patience = patience
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

    /// Waits for `process` to report it has recorded something, for up to `patience`, and returns it as a segment that
    /// `stop` asks to finish. Throws why it stopped first.
    static func started(_ process: Subprocess, patience: Duration, stop: @escaping @Sendable () async -> Void) async throws(ShotCommandError) -> FFmpegSegment {
        let watchdog = Task {
            if (try? await Task.sleep(for: patience)) != nil {
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
        return FFmpegSegment(process: process, progress: progress, patience: patience, stop: stop)
    }

    func finish() async throws(ShotCommandError) -> Double? {
        await stop()
        let (process, patience) = (process, patience)
        let watchdog = Task {
            if (try? await Task.sleep(for: patience)) != nil {
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
