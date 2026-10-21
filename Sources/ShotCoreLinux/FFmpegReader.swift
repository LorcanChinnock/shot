import Foundation

/// Linux's `VideoReader`: `ffprobe` for what a file holds, and `ffmpeg` for its frames, decoded to RGBA through a pipe,
/// and its sound, as mono floats. A project's frames are drawn as `FFmpegWriter` draws them.
public struct FFmpegReader: VideoReader {
    public init() {}

    public func info(of url: URL) async throws -> ImportedMedia {
        let probe = try await FFmpegTools.find().probe(url)
        return ImportedMedia(source: url, duration: probe.duration, size: probe.size, hasAudio: probe.hasAudio)
    }

    public func bitRates(of url: URL) async throws -> (video: Double, audio: Double) {
        try await FFmpegTools.find().probe(url).bitRates
    }

    public func syncTimes(atOrBefore times: [Double], in url: URL) async throws -> [Double]? {
        let packets = try await FFmpegTools.find().packets(url)
        guard !packets.syncTimes.isEmpty else {
            return nil
        }
        return times.map(packets.syncTime(atOrBefore:))
    }

    /// Decodes each run of nearby frames with one `ffmpeg`, which seeks to the sync frame before the run and picks its
    /// frames by when they're shown. Runs go in time order, so a frame asked for out of order waits for the ones before it.
    public func readFrames(of url: URL, at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws {
        let tools = try FFmpegTools.find()
        let probe = try await tools.probe(url)
        let packets = probe.hasVideo ? try await tools.packets(url) : FFmpeg.VideoPackets(times: [], isSync: [])
        guard let size = probe.size, !packets.times.isEmpty else {
            for time in times {
                try body(VideoFrame(requestedTime: time, decoded: .failure(ShotCommandError.data("\(url.lastPathComponent) has no video"))))
            }
            return
        }
        let (width, height) = FFmpeg.fitted(size, within: maxSize)
        let picks = times.map { packets.frame(at: $0, tolerance: tolerance)! }
        // How many of `times` still want each frame, so it's let go once they've had it.
        var wanted: [Int: Int] = [:]
        for pick in picks {
            wanted[pick, default: 0] += 1
        }
        var decoded: [Int: Result<PlatformImage, any Error>] = [:]
        var next = 0
        func handOver() throws {
            while next < times.count, let result = decoded[picks[next]] {
                let pick = picks[next]
                try body(VideoFrame(requestedTime: times[next], decoded: result.map { (packets.times[pick], $0) }))
                wanted[pick]! -= 1
                if wanted[pick] == 0 {
                    decoded[pick] = nil
                }
                next += 1
            }
        }
        let bytes = width * height * 4
        let version = await tools.version()
        for run in packets.runs(of: picks) {
            var failure: any Error = ShotCommandError.io("ffmpeg ended before it decoded the frame")
            do {
                try await Subprocess.run(tools.ffmpeg, FFmpeg.frameArguments(url.path, frames: run, of: packets, width: width, height: height, version: version)) { process in
                    for frame in run {
                        let pixels = await process.read(upTo: bytes)
                        guard let bitmap = Bitmap(width: width, height: height, pixels: pixels) else {
                            return
                        }
                        decoded[frame] = .success(BitmapImage(bitmap))
                        try handOver()
                    }
                }
            } catch let error as Subprocess.Failure {
                failure = error
            }
            for frame in run where decoded[frame] == nil && wanted[frame, default: 0] > 0 {
                decoded[frame] = .failure(failure)
            }
            try handOver()
        }
    }

    public func frames(of project: Project, canvasType: any Canvas.Type) async throws -> any VideoFrames {
        ProjectFrames(drawing: try await ProjectDrawing(project, canvasType: canvasType), canvasType: canvasType)
    }

    public func readMonoSamples(of url: URL, sampleRate: Double, _ body: ([Float]) throws -> Void) async throws {
        let tools = try FFmpegTools.find()
        let probe = try await tools.probe(url)
        guard probe.hasAudio else {
            return
        }
        let chunk = 16 * 1024
        let arguments = FFmpeg.sampleArguments(url.path, sampleRate: sampleRate, duration: probe.duration > 0 ? probe.duration : nil)
        try await Subprocess.run(tools.ffmpeg, arguments) { process in
            while true {
                let data = await process.read(upTo: chunk * MemoryLayout<Float>.size)
                var samples = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.size)
                _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
                if !samples.isEmpty {
                    try body(samples)
                }
                if samples.count < chunk {
                    return
                }
            }
        }
    }
}

/// A project read a frame at a time as `ProjectDrawing` draws it, the frame at each time asked for exactly, whatever the
/// tolerance.
struct ProjectFrames: VideoFrames {
    let drawing: ProjectDrawing
    let canvasType: any Canvas.Type

    var duration: Double { drawing.duration }
    var size: CGSize? { drawing.hasVideo ? drawing.compositor.project.outputRect.size : nil }

    /// Draws the frames in time order, so a frame asked for out of order waits for the ones before it.
    func readFrames(at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws {
        let order = times.indices.sorted { times[$0] < times[$1] }
        let output = drawing.compositor.project.outputRect.size
        let (width, height) = FFmpeg.fitted(output, within: maxSize)
        var early: [Int: VideoFrame] = [:]
        var next = 0
        var drawn = 0
        try await drawing.draw(at: order.map { times[$0] }) { result in
            let index = order[drawn]
            drawn += 1
            let decoded = result.flatMap { image -> Result<(time: Double, image: PlatformImage), any Error> in
                guard let fitted = fit(image, width: width, height: height) else {
                    return .failure(ShotCommandError.io("Couldn't make the frame at \(String(format: "%.3f", times[index])) s smaller"))
                }
                return .success((times[index], fitted))
            }
            early[index] = VideoFrame(requestedTime: times[index], decoded: decoded)
            while let frame = early.removeValue(forKey: next) {
                try body(frame)
                next += 1
            }
        }
    }

    /// `image` drawn at `width` × `height`, unless it's that size already.
    private func fit(_ image: PlatformImage, width: Int, height: Int) -> PlatformImage? {
        guard image.width != width || image.height != height else {
            return image
        }
        guard let ctx = canvasType.init(width: width, height: height, format: .sRGB) else {
            return nil
        }
        ctx.setInterpolation(.high)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
