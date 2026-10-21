import Foundation

/// The `VideoReader`, `VideoAssembler` and `VideoWriter` the commands and MCP tools take on Linux until the video ones
/// come with #753, on `FFmpegReader`, `FFmpegAssembler` and `FFmpegWriter`: each call answers
/// `ShotCommandError.notOnLinuxYet`. ShotCommands+Defaults.swift turns the video commands away before they get here, so
/// this only stands in for the parameters.
struct NoVideo: VideoReader, VideoAssembler, VideoWriter {
    func info(of url: URL) async throws -> ImportedMedia { throw ShotCommandError.notOnLinuxYet }
    func bitRates(of url: URL) async throws -> (video: Double, audio: Double) { throw ShotCommandError.notOnLinuxYet }
    func syncTimes(atOrBefore times: [Double], in url: URL) async throws -> [Double]? { throw ShotCommandError.notOnLinuxYet }
    func readFrames(of url: URL, at times: [Double], maxSize: CGSize, tolerance: Double?, _ body: (VideoFrame) throws -> Void) async throws {
        throw ShotCommandError.notOnLinuxYet
    }
    func frames(of project: Project, canvasType: any Canvas.Type) async throws -> any VideoFrames { throw ShotCommandError.notOnLinuxYet }
    func readMonoSamples(of url: URL, sampleRate: Double, _ body: ([Float]) throws -> Void) async throws { throw ShotCommandError.notOnLinuxYet }
    func trim(_ input: URL, kept: [TrimRange], speed: Double, muted: Bool, to output: URL, as fileType: String?) async throws -> Bool {
        throw ShotCommandError.notOnLinuxYet
    }
    func concatenate(_ segments: [URL], audio: [VideoConcatenator.SegmentAudio], to output: URL, muting muted: CutList) async throws {
        throw ShotCommandError.notOnLinuxYet
    }
    func write(_ project: Project, to output: URL, as fileType: String, canvasType: any Canvas.Type, codec: (_ frameRate: Int) -> VideoCodec) async throws {
        throw ShotCommandError.notOnLinuxYet
    }
}
