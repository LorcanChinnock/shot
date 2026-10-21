import Foundation
import Synchronization

/// The `ffmpeg` and `ffprobe` programs `FFmpegReader` and `FFmpegAssembler` run: those `SHOT_FFMPEG` and `SHOT_FFPROBE`
/// name, else the first on the `PATH`.
public struct FFmpegTools: Sendable {
    public let ffmpeg: String
    public let ffprobe: String

    /// Why there are none to run.
    static let missing = "Shot reads, trims and joins video with ffmpeg and ffprobe, and can't find them. \(FFmpeg.install)"

    /// The programs `environment` finds, as `FFmpeg.locate` looks for them.
    static func located(environment: [String: String]) -> (ffmpeg: String?, ffprobe: String?) {
        let isExecutable = { FileManager.default.isExecutableFile(atPath: $0) }
        return (
            FFmpeg.locate("ffmpeg", override: environment["SHOT_FFMPEG"], path: environment["PATH"], isExecutable: isExecutable),
            FFmpeg.locate("ffprobe", override: environment["SHOT_FFPROBE"], path: environment["PATH"], isExecutable: isExecutable)
        )
    }

    /// Both programs, or `ShotCommandError.unavailable` saying how to install them.
    public static func find(environment: [String: String] = ProcessInfo.processInfo.environment) throws(ShotCommandError) -> FFmpegTools {
        let found = located(environment: environment)
        guard let ffmpeg = found.ffmpeg, let ffprobe = found.ffprobe else {
            throw .unavailable(missing)
        }
        return FFmpegTools(ffmpeg: ffmpeg, ffprobe: ffprobe)
    }

    /// ffmpeg's version, which it's asked for once.
    func version() async -> String? {
        if let known = Self.versions.withLock({ $0[ffmpeg] }) {
            return known
        }
        let version = (try? await Subprocess.output(ffmpeg, ["-version"])).flatMap { FFmpeg.version(from: String(decoding: $0, as: UTF8.self)) }
        Self.versions.withLock { $0[ffmpeg] = version }
        return version
    }

    /// The version of each ffmpeg asked, or `nil` where it didn't say.
    private static let versions = Mutex<[String: String?]>([:])

    /// What `ffprobe` says of `url`'s streams and container.
    func probe(_ url: URL) async throws -> FFmpeg.Probe {
        try FFmpeg.Probe(json: try await Subprocess.output(ffprobe, FFmpeg.probeArguments(url.path)))
    }

    /// The frames of `url`'s first video stream, when each is shown and which are sync frames.
    func packets(_ url: URL) async throws -> FFmpeg.VideoPackets {
        FFmpeg.VideoPackets(compact: String(decoding: try await Subprocess.output(ffprobe, FFmpeg.packetArguments(url.path)), as: UTF8.self))
    }

    /// Runs `job` with its concat list in `scratch`, which exists.
    func run(_ job: FFmpeg.Job, listedAt concatList: URL) async throws {
        if let list = job.concatList {
            try Data(list.utf8).write(to: concatList)
        }
        for arguments in job.runs {
            _ = try await Subprocess.output(ffmpeg, arguments)
        }
    }

    /// What `shot doctor` says of ffmpeg: where the programs are, ffmpeg's version, and the encoders it has.
    public static func doctorFacts(environment: [String: String] = ProcessInfo.processInfo.environment) async -> Doctor.FFmpegFacts {
        let found = located(environment: environment)
        var facts = Doctor.FFmpegFacts(ffmpeg: found.ffmpeg, ffprobe: found.ffprobe)
        if let ffmpeg = found.ffmpeg {
            facts.version = await FFmpegTools(ffmpeg: ffmpeg, ffprobe: found.ffprobe ?? "").version()
            facts.encoders = (try? await Subprocess.output(ffmpeg, ["-hide_banner", "-encoders"])).map { FFmpeg.encoders(from: String(decoding: $0, as: UTF8.self)) } ?? []
        }
        return facts
    }
}

/// A folder of its own in the temporary directory for one job's lists and intermediate files, removed after `body`.
func withScratchFolder<T>(_ body: (URL) async throws -> T) async throws -> T {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Shot/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    return try await body(folder)
}
