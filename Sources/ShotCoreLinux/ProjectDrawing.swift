import Foundation

/// A project's frames as `PortableCompositor` draws them, from the frames ffmpeg decodes of each clip's source, with what
/// a Mac's composition of it would say: how long it plays, how fast, and the sound under it. `FFmpegWriter` encodes the
/// frames, and `FFmpegReader.frames(of:canvasType:)` hands them on, so a GIF shows what an export does.
struct ProjectDrawing: Sendable {
    let compositor: PortableCompositor
    let tools: FFmpegTools
    /// ffmpeg's version, for the option that passes frames through.
    let version: String?
    /// The frames of each video clip's source.
    let packets: [URL: FFmpeg.VideoPackets]
    /// How long it plays, to the end of its last picture or sound, as a Mac's composition does.
    let duration: Double
    /// How many frames a second it's drawn at, as a Mac draws it.
    let frameRate: Int
    /// The sound of each clip on a track that isn't muted, from sources that have some.
    let sounds: [FFmpeg.Sound]
    /// Whether it has any pictures.
    let hasVideo: Bool

    /// Reads what `project`'s sources hold. Throws `CompositionBuilder.BuildError` when one can't be read, or a video
    /// clip's has no video.
    init(_ project: Project, canvasType: any Canvas.Type) async throws {
        let tools = try FFmpegTools.find()
        self.tools = tools
        compositor = PortableCompositor(project: project, canvasType: canvasType)
        version = await tools.version()
        var probes: [URL: FFmpeg.Probe] = [:]
        func probe(_ url: URL) async throws -> FFmpeg.Probe {
            if let known = probes[url] {
                return known
            }
            do {
                let probe = try await tools.probe(url)
                probes[url] = probe
                return probe
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw CompositionBuilder.BuildError.cannotInsert(url.lastPathComponent)
            }
        }
        var found: [URL: FFmpeg.VideoPackets] = [:]
        var rates: [Double] = []
        var end = 0.0
        let clips = project.videoTracks.flatMap(\.clips)
        for clip in clips {
            let source = try await probe(clip.source)
            if found[clip.source] == nil, source.hasVideo {
                found[clip.source] = try await tools.packets(clip.source)
            }
            guard found[clip.source]?.times.isEmpty == false else {
                throw CompositionBuilder.BuildError.noVideo(clip.source.lastPathComponent)
            }
            rates.append(source.frameRate ?? 30)
            end = max(end, clip.end)
        }
        var sounds: [FFmpeg.Sound] = []
        for track in project.tracks where track.kind == .audio && !track.isMuted {
            for clip in track.clips {
                guard try await probe(clip.source).hasAudio else {
                    continue
                }
                sounds.append(FFmpeg.Sound(clip, path: clip.source.path))
                end = max(end, clip.end)
            }
        }
        packets = found
        self.sounds = sounds
        duration = end
        frameRate = FFmpeg.frameRate(of: rates)
        hasVideo = !clips.isEmpty
    }

    /// When each frame it encodes is shown: one every `frameRate`th of a second until it ends.
    var frameTimes: [Double] {
        let count = max(1, Int((duration * Double(frameRate) - 1e-6).rounded(.up)))
        return (0..<count).map { Double($0) / Double(frameRate) }
    }

    /// Draws the frame at each of `times`, which mustn't go back, handing each to `body` in order with the error that
    /// kept it from being drawn. Each clip's frames are decoded by an ffmpeg of its own, from when it's first shown
    /// until it's last shown, which decodes the next while this one's drawn.
    func draw(at times: [Double], _ body: (Result<PlatformImage, any Error>) async throws -> Void) async throws {
        // Which frame of its source each clip shows at each time, and the last time it shows.
        var shown: [[(clip: UUID, frame: Int)]] = []
        var needed: [UUID: [Int]] = [:]
        var clips: [UUID: Clip] = [:]
        var lastShown: [UUID: Int] = [:]
        for (index, time) in times.enumerated() {
            shown.append(compositor.pictures(at: time).compactMap { picture in
                guard let frame = packets[picture.clip.source]?.frame(at: picture.sourceTime, tolerance: 0) else {
                    return nil
                }
                needed[picture.clip.id, default: []].append(frame)
                clips[picture.clip.id] = picture.clip
                lastShown[picture.clip.id] = index
                return (picture.clip.id, frame)
            })
        }
        var streams: [UUID: ClipStream] = [:]
        for (index, time) in times.enumerated() {
            try Task.checkCancellation()
            var pictures: [UUID: PlatformImage] = [:]
            var failure: (any Error)?
            for (id, frame) in shown[index] {
                if streams[id] == nil, let clip = clips[id], let packets = packets[clip.source] {
                    streams[id] = ClipStream(clip, packets: packets, frames: needed[id] ?? [], tools: tools, version: version)
                }
                do {
                    pictures[id] = try await streams[id]?.frame(frame)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failure = failure ?? error
                }
            }
            // A clip's ffmpeg ends once it's shown its last frame.
            for (id, last) in lastShown where last == index {
                streams[id] = nil
            }
            if let failure {
                try await body(.failure(failure))
            } else if let frame = compositor.frame(at: time, pictures: pictures) {
                try await body(.success(frame))
            } else {
                try await body(.failure(ShotCommandError.io("Couldn't draw the frame at \(String(format: "%.3f", time)) s")))
            }
        }
    }
}

/// The frames of one clip's source that a drawing needs, in order, at the clip's size, decoded by one ffmpeg for each
/// run of `FFmpeg.VideoPackets.runs`. It reads one frame ahead, so ffmpeg decodes the next while the last is drawn.
/// When a run ends cleanly before all its frames, as where a file lists a frame it then leaves out, the last frame it
/// gave stands in for the rest, as a player would hold it.
private final class ClipStream {
    private let source: URL
    private let packets: FFmpeg.VideoPackets
    private let width: Int
    private let height: Int
    private let tools: FFmpegTools
    private let version: String?
    /// The runs still to start.
    private var runs: ArraySlice<[Int]>
    /// The frames the running ffmpeg has still to hand over, in order.
    private var coming: ArraySlice<Int> = []
    private var process: Subprocess?
    /// The read of the next frame, under way.
    private var ahead: Task<Data, Never>?
    private var current: (frame: Int, image: PlatformImage)?
    /// The last frame of a run that ended early, through which `current` is held.
    private var heldThrough = -1
    private var failure: (any Error)?

    private static let log = ShotLog.shot("video")

    init(_ clip: Clip, packets: FFmpeg.VideoPackets, frames: [Int], tools: FFmpegTools, version: String?) {
        source = clip.source
        self.packets = packets
        width = max(1, Int(clip.size.width.rounded()))
        height = max(1, Int(clip.size.height.rounded()))
        self.tools = tools
        self.version = version
        runs = packets.runs(of: frames)[...]
    }

    private var bytes: Int { width * height * 4 }

    /// Frame `frame` of the source, which is one it was made with, at or after the last asked for.
    func frame(_ frame: Int) async throws -> PlatformImage {
        if let current, current.frame == frame || frame <= heldThrough {
            return current.image
        }
        if let failure {
            throw failure
        }
        do {
            while true {
                if coming.isEmpty {
                    try start()
                }
                let next = coming.removeFirst()
                guard let process else {
                    throw ShotCommandError.io("ffmpeg isn't decoding \(source.lastPathComponent)")
                }
                let bytes = bytes
                let data = await (ahead ?? Task { await process.read(upTo: bytes) }).value
                ahead = nil
                guard let bitmap = Bitmap(width: width, height: height, pixels: data) else {
                    // It ended early: say why if it failed, else hold the frame before.
                    try await process.wait()
                    guard let current else {
                        throw ShotCommandError.io("ffmpeg ended before it decoded \(source.lastPathComponent) at \(String(format: "%.3f", packets.times[next])) s")
                    }
                    Self.log.error("ffmpeg ended before it decoded \(self.source.lastPathComponent, privacy: .public) at \(self.packets.times[next], privacy: .public) s, so the frame before is shown")
                    heldThrough = coming.last ?? next
                    coming = []
                    self.process = nil
                    return current.image
                }
                if coming.isEmpty {
                    self.process = nil
                } else {
                    ahead = Task { await process.read(upTo: bytes) }
                }
                guard next < frame else {
                    let image = BitmapImage(bitmap)
                    current = (next, image)
                    return image
                }
            }
        } catch {
            failure = error
            process = nil
            throw error
        }
    }

    /// Starts the ffmpeg that decodes the next run.
    private func start() throws {
        guard let run = runs.popFirst() else {
            throw ShotCommandError.io("No frame of \(source.lastPathComponent) is left to decode")
        }
        process = try Subprocess(tools.ffmpeg, FFmpeg.frameArguments(source.path, frames: run, of: packets, width: width, height: height, version: version))
        coming = run[...]
        let (process, bytes) = (process!, bytes)
        ahead = Task { await process.read(upTo: bytes) }
    }
}
