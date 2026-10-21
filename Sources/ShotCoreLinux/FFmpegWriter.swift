import Foundation

/// Linux's `VideoWriter`: each frame drawn by `PortableCompositor` from frames ffmpeg decodes, piped as RGBA to one more
/// ffmpeg that encodes them, and mixes the project's sound under them in its filter graph, each clip at its place and
/// volume, as a Mac's audio mix does. It draws the next frame while ffmpeg encodes the last.
public struct FFmpegWriter: VideoWriter {
    public init() {}

    private static let log = ShotLog.shot("video")

    public func write(_ project: Project, to output: URL, as fileType: String, canvasType: any Canvas.Type, codec: (_ frameRate: Int) -> VideoCodec) async throws {
        guard let muxer = FFmpeg.muxer(for: fileType) else {
            throw ProjectExporter.ExportError.unsupportedFileType
        }
        let drawing = try await ProjectDrawing(project, canvasType: canvasType)
        let hevc = codec(drawing.frameRate) == .hevc
        if hevc, await !drawing.tools.encoders().contains(FFmpeg.hevcEncoder) {
            throw ShotCommandError.unavailable(Self.noHEVC)
        }
        let size = project.outputRect.size
        let (width, height) = (Int(size.width), Int(size.height))
        let arguments = FFmpeg.writeArguments(
            width: width, height: height, frameRate: drawing.frameRate, hevc: hevc, sounds: drawing.sounds, duration: drawing.duration, muxer: muxer, output: output.path
        )
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        do {
            try await Subprocess.run(drawing.tools.ffmpeg, arguments, writable: true) { encoder in
                var writing: Task<Bool, Never>?
                /// Waits for the frame before to be taken, and throws why ffmpeg stopped if it wasn't.
                func written() async throws {
                    if let writing, await !writing.value {
                        try await encoder.wait()
                        throw ShotCommandError.io("ffmpeg stopped reading frames")
                    }
                }
                try await drawing.draw(at: drawing.frameTimes) { result in
                    let frame = try result.get()
                    guard frame.width == width, frame.height == height else {
                        throw ShotCommandError.io("A frame came out \(frame.width) × \(frame.height) rather than \(width) × \(height)")
                    }
                    try await written()
                    let pixels = frame.bitmap.pixels
                    writing = Task { await encoder.write(pixels) }
                }
                try await written()
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            // ffmpeg failing, or a frame that wouldn't decode or draw, fails the export; the rest say what's missing.
            switch error {
            case is Subprocess.Failure, ShotCommandError.io:
                Self.log.error("Couldn't write \(output.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                throw ProjectExporter.ExportError.failed
            default:
                throw error
            }
        }
    }

    /// Why a project that needs HEVC can't be written.
    static let noHEVC = "This video needs HEVC, for its frame rate or size, and ffmpeg has no \(FFmpeg.hevcEncoder) to encode it. Install an ffmpeg built with \(FFmpeg.hevcEncoder), such as your distribution's ffmpeg package."
}
