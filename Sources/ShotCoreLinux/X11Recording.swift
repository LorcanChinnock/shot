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
        // `q` has it finish the file, where killing it would leave the file without its index. It may have stopped already.
        return try await FFmpegSegment.started(process, patience: Self.patience) {
            _ = await process.write(FFmpeg.stopKey)
            await process.closeInput()
        }
    }
}
