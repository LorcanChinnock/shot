import Foundation
import Testing
@testable import ShotModel

// MARK: Finding the programs

@Test func ffmpegIsFoundWhereTheOverrideSaysThenOnThePath() {
    let installed: Set<String> = ["/opt/ffmpeg/bin/ffmpeg", "/usr/bin/ffmpeg"]
    let isExecutable = { installed.contains($0) }
    #expect(FFmpeg.locate("ffmpeg", override: "/opt/ffmpeg/bin/ffmpeg", path: "/usr/bin", isExecutable: isExecutable) == "/opt/ffmpeg/bin/ffmpeg")
    // An override that names nothing runnable falls back to the path.
    #expect(FFmpeg.locate("ffmpeg", override: "/missing/ffmpeg", path: "/usr/local/bin:/usr/bin/", isExecutable: isExecutable) == "/usr/bin/ffmpeg")
    #expect(FFmpeg.locate("ffmpeg", override: "", path: "::/usr/bin", isExecutable: isExecutable) == "/usr/bin/ffmpeg")
    #expect(FFmpeg.locate("ffprobe", override: nil, path: "/usr/bin", isExecutable: isExecutable) == nil)
    #expect(FFmpeg.locate("ffmpeg", override: nil, path: nil, isExecutable: isExecutable) == nil)
}

@Test func ffmpegsVersionAndEncodersAreReadFromWhatItPrints() {
    #expect(FFmpeg.version(from: "ffmpeg version 6.1.1-3ubuntu5 Copyright (c) 2000-2023 the FFmpeg developers\nbuilt with gcc 13") == "6.1.1-3ubuntu5")
    #expect(FFmpeg.version(from: "something else") == nil)
    #expect(FFmpeg.version(from: "") == nil)
    let encoders = """
    Encoders:
     V..... = Video
     A..... = Audio
     ------
     V....D libx264              libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (codec h264)
     V....D libx265              libx265 H.265 / HEVC (codec hevc)
     A....D aac                  AAC (Advanced Audio Coding)
    """
    #expect(FFmpeg.encoders(from: encoders) == ["libx264", "libx265", "aac"])
}

// MARK: Probing

private let rotatedProbe = """
{
    "streams": [
        {
            "codec_type": "video", "width": 160, "height": 90, "bit_rate": "8024",
            "disposition": { "default": 1, "attached_pic": 0 },
            "tags": { "language": "und" },
            "side_data_list": [
                { "side_data_type": "Display Matrix", "displaymatrix": "\\n00000000: 0 65536 0\\n", "rotation": -90 }
            ]
        },
        { "codec_type": "audio", "bit_rate": "17292", "disposition": { "attached_pic": 0 } }
    ],
    "format": { "start_time": "0.000000", "duration": "1.000000", "bit_rate": "26000" }
}
"""

@Test func aProbeReadsTheDurationTheTurnedSizeAndTheSound() throws {
    let probe = try FFmpeg.Probe(json: Data(rotatedProbe.utf8))
    #expect(probe.duration == 1 && probe.startTime == 0)
    #expect(probe.size == CGSize(width: 90, height: 160))
    #expect(probe.hasVideo && probe.hasAudio)
    #expect(probe.bitRates == (video: 8024, audio: 17292))
}

@Test func aProbeLeavesOutCoverArtAndFillsInAMissingVideoRate() throws {
    let song = """
    {"streams": [{"codec_type": "audio", "bit_rate": "128000"}, {"codec_type": "video", "width": 600, "height": 600, "disposition": {"attached_pic": 1}}],
     "format": {"duration": "180.5"}}
    """
    let probe = try FFmpeg.Probe(json: Data(song.utf8))
    #expect(probe.size == nil && !probe.hasVideo && probe.hasAudio && probe.duration == 180.5)

    // Matroska keeps its rates in tags, or not at all, and an old file says it's turned in a tag.
    let film = """
    {"streams": [{"codec_type": "video", "width": 1920, "height": 1080, "tags": {"rotate": "270"}}, {"codec_type": "audio", "tags": {"BPS": "96000"}}],
     "format": {"duration": "10", "start_time": "1.5", "bit_rate": "2096000"}}
    """
    let turned = try FFmpeg.Probe(json: Data(film.utf8))
    #expect(turned.size == CGSize(width: 1080, height: 1920) && turned.startTime == 1.5)
    #expect(turned.bitRates == (video: 2_000_000, audio: 96000))
    #expect(throws: (any Error).self) { try FFmpeg.Probe(json: Data("not json".utf8)) }
}

/// Six frames at 10 fps, out of order as B-frames come, a sync frame every three, in a file that starts at 1 s.
private let packets = FFmpeg.VideoPackets(compact: """
packet|pts_time=1.000000|flags=K__
packet|pts_time=1.200000|flags=___
packet|pts_time=1.100000|flags=___
packet|pts_time=1.300000|flags=K__
packet|pts_time=1.500000|flags=___
packet|pts_time=1.400000|flags=___
packet|pts_time=N/A|flags=___
packet|pts_time=0.900000|flags=K_D
format|start_time=1.000000
""")

@Test func packetsAreShownInTimeOrderFromTheStartOfTheFile() {
    #expect(packets.startTime == 1)
    #expect(packets.times.map { ($0 * 10).rounded() } == [0, 1, 2, 3, 4, 5])
    #expect(packets.isSync == [true, false, false, true, false, false])
    #expect(packets.syncTimes.map { ($0 * 10).rounded() } == [0, 3])
}

@Test func theSyncFrameAtOrBeforeATimeIsTheLastThatStartsByThen() {
    #expect(packets.syncTime(atOrBefore: 0.25) == 0)
    #expect(abs(packets.syncTime(atOrBefore: 0.3) - 0.3) < 1e-9)
    #expect(abs(packets.syncTime(atOrBefore: 9) - 0.3) < 1e-9)
    // Before the first, there's none, so it's the time itself.
    #expect(packets.syncTime(atOrBefore: -1) == -1)
}

@Test func theFrameForATimeIsTheOneShownThenUnlessASyncFrameIsWithinTolerance() {
    #expect(packets.frame(at: 0.25, tolerance: 0) == 2)
    #expect(packets.frame(at: 0.25, tolerance: 0.05) == 3)
    #expect(packets.frame(at: 0.15, tolerance: 0.04) == 1)
    #expect(packets.frame(at: 0.45, tolerance: nil) == 3)
    #expect(packets.frame(at: 0.2, tolerance: 0) == 2)
    #expect(packets.frame(at: -1, tolerance: 0) == 0)
    #expect(packets.frame(at: 99, tolerance: 0) == 5)
    #expect(FFmpeg.VideoPackets(times: [], isSync: []).frame(at: 0, tolerance: nil) == nil)
}

@Test func framesSplitIntoRunsWhereSeekingSkipsDecoding() {
    #expect(packets.runs(of: [5, 1, 1, 0]) == [[0, 1, 5]])
    #expect(packets.runs(of: [5, 1, 0], gap: 0.1) == [[0, 1], [5]])
    // Seeking to the sync frame at 0.3 skips decoding the 0.2 s from the frame at 0.1.
    #expect(packets.runs(of: [1, 3], gap: 0.25) == [[1, 3]])
    #expect(packets.runs(of: [1, 3], gap: 0.15) == [[1], [3]])
    #expect(packets.runs(of: []) == [])
}

// MARK: Reading

@Test func framesFitTheMaximumKeepingTheirShapeWithoutGrowing() {
    #expect(FFmpeg.fitted(CGSize(width: 90, height: 160), within: CGSize(width: 45, height: 0)) == (45, 80))
    #expect(FFmpeg.fitted(CGSize(width: 1920, height: 1080), within: CGSize(width: 160, height: 160)) == (160, 90))
    #expect(FFmpeg.fitted(CGSize(width: 320, height: 240), within: .zero) == (320, 240))
    #expect(FFmpeg.fitted(CGSize(width: 320, height: 240), within: CGSize(width: 1000, height: 1000)) == (320, 240))
    #expect(FFmpeg.fitted(CGSize(width: 1000, height: 1), within: CGSize(width: 10, height: 0)) == (10, 1))
}

@Test func framesAreDecodedFromTheSyncFrameBeforeTheFirstAndPickedByTime() {
    let arguments = FFmpeg.frameArguments("/v/a.mp4", frames: [3, 5], of: packets, width: 80, height: 45)
    #expect(arguments == [
        "-v", "error", "-nostdin", "-noaccurate_seek", "-ss", "0.3", "-copyts", "-i", "/v/a.mp4", "-map", "0:v:0",
        "-vf", "select='between(t,1.2995,1.3005)+between(t,1.4995,1.5005)',scale=80:45",
        "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1",
    ])
    #expect(FFmpeg.frameArguments("/v/a.mp4", frames: [0], of: packets, width: 8, height: 8, version: "4.4.2-0ubuntu0.22.04.1").contains("-vsync"))
    // From the first frame there's no seeking.
    #expect(!FFmpeg.frameArguments("/v/a.mp4", frames: [0], of: packets, width: 8, height: 8).contains("-ss"))
}

@Test func framesPassThroughWithTheOptionTheVersionTakes() {
    #expect(FFmpeg.passthrough(version: "4.4.2-0ubuntu0.22.04.1") == ["-vsync", "passthrough"])
    #expect(FFmpeg.passthrough(version: "5.0.3") == ["-vsync", "passthrough"])
    #expect(FFmpeg.passthrough(version: "5.1.6-0+deb12u1") == ["-fps_mode", "passthrough"])
    #expect(FFmpeg.passthrough(version: "n7.0") == ["-fps_mode", "passthrough"])
    #expect(FFmpeg.passthrough(version: "9.0.2") == ["-fps_mode", "passthrough"])
    #expect(FFmpeg.passthrough(version: "N-112345-gabcdef") == ["-fps_mode", "passthrough"])
    #expect(FFmpeg.passthrough(version: nil) == ["-fps_mode", "passthrough"])
}

@Test func samplesAreDecodedAsMonoFloats() {
    #expect(FFmpeg.sampleArguments("/v/a.mp4", sampleRate: 8000) == [
        "-v", "error", "-nostdin", "-i", "/v/a.mp4", "-map", "0:a:0", "-ac", "1", "-ar", "8000", "-f", "f32le", "pipe:1",
    ])
    #expect(FFmpeg.sampleArguments("/v/a.mp4", sampleRate: 44100, duration: 2.5) == [
        "-v", "error", "-nostdin", "-i", "/v/a.mp4", "-map", "0:a:0", "-t", "2.5", "-ac", "1", "-ar", "44100", "-f", "f32le", "pipe:1",
    ])
}

// MARK: Trimming and joining

@Test func fileTypesMapToExtensionsAndFormats() {
    #expect(FFmpeg.fileType(forExtension: "MOV") == "com.apple.quicktime-movie")
    #expect(FFmpeg.fileType(forExtension: "mp4") == "public.mpeg-4")
    #expect(FFmpeg.fileType(forExtension: "gif") == nil)
    #expect(FFmpeg.fileType(forExtension: "") == nil)
    #expect(FFmpeg.muxer(for: "public.mpeg-4") == "mp4")
    #expect(FFmpeg.muxer(for: "com.apple.m4v-video") == "mp4")
    #expect(FFmpeg.muxer(for: "com.compuserve.gif") == nil)
}

private let source = FFmpeg.Source(path: "/v/in.mp4", hasAudio: true)

private func trim(_ kept: [TrimRange], speed: Double = 1, muted: Bool = false, source: FFmpeg.Source = source) -> FFmpeg.Job {
    FFmpeg.trim(source, kept: kept, speed: speed, muted: muted, to: "/v/out.mov", as: "mov", scratch: "/s")
}

@Test func oneSectionIsCopiedFromASeek() {
    let job = trim([TrimRange(start: 0.15, end: 0.45, duration: 0.6)])
    #expect(job.copiesVideo && job.concatList == nil)
    #expect(job.runs == [[
        "-v", "error", "-nostdin", "-ss", "0.15", "-t", "0.3", "-i", "/v/in.mp4", "-map", "0:v", "-map", "0:a", "-c", "copy", "-f", "mov", "-y", "/v/out.mov",
    ]])
    #expect(!trim([TrimRange(start: 0.15, end: 0.45, duration: 0.6)], muted: true).runs[0].contains("0:a"))
    let encoded = FFmpeg.trim(source, kept: [TrimRange(start: 0.15, end: 0.45, duration: 0.6)], speed: 1, muted: false, to: "/v/out.mov", as: "mov", scratch: "/s", copying: false)
    #expect(!encoded.copiesVideo && encoded.runs[0].contains("libx264"))
}

@Test func severalSectionsAreEncodedAgain() {
    // Even where each starts on a sync frame.
    let job = trim([TrimRange(start: 0, end: 0.2, duration: 0.6), TrimRange(start: 0.4, end: 0.6, duration: 0.6)], speed: 2)
    #expect(!job.copiesVideo && job.concatList == nil)
    let graph = [
        "[0:v:0]split=2[vs0][vs1]", "[0:a:0]asplit=2[as0][as1]",
        "[vs0]trim=start=0:end=0.2,setpts=PTS-STARTPTS[v0]", "[as0]atrim=start=0:end=0.2,asetpts=PTS-STARTPTS[a0]",
        "[vs1]trim=start=0.4:end=0.6,setpts=PTS-STARTPTS[v1]", "[as1]atrim=start=0.4:end=0.6,asetpts=PTS-STARTPTS[a1]",
        "[v0][a0][v1][a1]concat=n=2:v=1:a=1[vc][ac]", "[vc]setpts=PTS/2[v]", "[ac]atempo=2[a]",
    ].joined(separator: ";")
    #expect(job.runs == [[
        "-v", "error", "-nostdin", "-i", "/v/in.mp4", "-filter_complex", graph, "-map", "[v]", "-map", "[a]",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-f", "mov", "-y", "/v/out.mov",
    ]])

    let silent = trim([TrimRange(start: 0.1, end: 0.2, duration: 0.6)] + [TrimRange(start: 0.4, end: 0.6, duration: 0.6)], muted: true)
    #expect(silent.runs == [[
        "-v", "error", "-nostdin", "-i", "/v/in.mp4", "-filter_complex",
        "[0:v:0]split=2[vs0][vs1];[vs0]trim=start=0.1:end=0.2,setpts=PTS-STARTPTS[v0];[vs1]trim=start=0.4:end=0.6,setpts=PTS-STARTPTS[v1];[v0][v1]concat=n=2:v=1:a=0[vc];[vc]null[v]",
        "-map", "[v]", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p", "-f", "mov", "-y", "/v/out.mov",
    ]])
}

@Test func aCopiedSectionAtAnotherSpeedIsCopiedThenRetimed() {
    let job = trim([TrimRange(start: 0.15, end: 0.45, duration: 0.6)], speed: 0.25)
    #expect(job.copiesVideo)
    #expect(job.runs == [
        ["-v", "error", "-nostdin", "-ss", "0.15", "-t", "0.3", "-i", "/v/in.mp4", "-map", "0:v", "-c", "copy", "-f", "mp4", "-y", "/s/video.mp4"],
        [
            "-v", "error", "-nostdin", "-itsscale", "4", "-i", "/s/video.mp4", "-ss", "0.15", "-t", "0.3", "-i", "/v/in.mp4", "-map", "0:v", "-c:v", "copy",
            "-map", "1:a", "-filter:a", "atempo=0.5,atempo=0.5", "-c:a", "aac", "-b:a", "160k", "-f", "mov", "-y", "/v/out.mov",
        ],
    ])
    let silent = trim([TrimRange(start: 0.15, end: 0.45, duration: 0.6)], speed: 3, source: FFmpeg.Source(path: "/v/in.mp4", hasAudio: false))
    #expect(silent.runs[1] == ["-v", "error", "-nostdin", "-itsscale", "0.333333", "-i", "/s/video.mp4", "-map", "0:v", "-c:v", "copy", "-f", "mov", "-y", "/v/out.mov"])
}

@Test func tempoIsChainedWithinWhatOneFilterTakes() {
    #expect(FFmpeg.tempo(1.5) == "atempo=1.5")
    #expect(FFmpeg.tempo(8) == "atempo=2,atempo=2,atempo=2")
    #expect(FFmpeg.tempo(0.3) == "atempo=0.5,atempo=0.6")
}

private func join(sounds: [FFmpeg.SegmentSound] = [], hasAudio: Bool = true, muted: [Range<Double>] = []) -> FFmpeg.Job {
    FFmpeg.concatenate(["/r/a.mp4", "/r/it's.mp4"], durations: [2, 1.5], sounds: sounds, hasAudio: hasAudio, muting: muted, to: "/r/out.mp4", concatList: "/s/list.txt")
}

@Test func segmentsAreJoinedByCopying() {
    let job = join()
    #expect(job.concatList == "file '/r/a.mp4'\nfile '/r/it'\\''s.mp4'\n")
    #expect(job.runs == [["-v", "error", "-nostdin", "-f", "concat", "-safe", "0", "-i", "/s/list.txt", "-map", "0:v?", "-map", "0:a?", "-c", "copy", "-f", "mp4", "-y", "/r/out.mp4"]])
    #expect(join(hasAudio: false, muted: [1..<2]).runs == job.runs)
}

@Test func mutedStretchesOfAJoinAreEncodedSilent() {
    #expect(join(muted: [1.5..<2.5, 3..<10]).runs == [[
        "-v", "error", "-nostdin", "-f", "concat", "-safe", "0", "-i", "/s/list.txt", "-map", "0:v", "-map", "0:a", "-c:v", "copy",
        "-filter:a", "volume=0:enable='between(t,1.5,2.5)+between(t,3,10)'", "-c:a", "aac", "-b:a", "160k", "-f", "mp4", "-y", "/r/out.mp4",
    ]])
}

@Test func aJoinsOwnSoundFilesAreLaidAtEachSegmentAndMixed() {
    let sounds = [FFmpeg.SegmentSound(system: "/r/a-system.m4a", microphone: "/r/a-mic.m4a"), FFmpeg.SegmentSound(system: nil, microphone: "/r/b-mic.m4a")]
    let job = join(sounds: sounds, muted: [1..<2.5])
    let silence = "volume=0:enable='between(t,1,2.5)'"
    #expect(job.runs == [[
        "-v", "error", "-nostdin", "-f", "concat", "-safe", "0", "-i", "/s/list.txt", "-i", "/r/a-system.m4a", "-i", "/r/a-mic.m4a", "-i", "/r/b-mic.m4a",
        "-filter_complex", [
            "[1:a:0]atrim=end=2,asetpts=PTS-STARTPTS,adelay=delays=0:all=1[s1]",
            "[2:a:0]atrim=end=2,asetpts=PTS-STARTPTS,adelay=delays=0:all=1,\(silence)[s2]",
            "[3:a:0]atrim=end=1.5,asetpts=PTS-STARTPTS,adelay=delays=2000:all=1,\(silence)[s3]",
            "[s1][s2][s3]amix=inputs=3:normalize=0:duration=longest,atrim=end=3.5[a]",
        ].joined(separator: ";"),
        "-map", "0:v", "-c:v", "copy", "-map", "[a]", "-c:a", "aac", "-b:a", "160k", "-f", "mp4", "-y", "/r/out.mp4",
    ]])
    let one = join(sounds: [FFmpeg.SegmentSound(system: nil, microphone: nil), FFmpeg.SegmentSound(system: "/r/b.m4a", microphone: nil)])
    #expect(one.runs[0].contains("[1:a:0]atrim=end=1.5,asetpts=PTS-STARTPTS,adelay=delays=2000:all=1[s1];[s1]atrim=end=3.5[a]"))
    // With no sound files at all, the joined video has no sound.
    let none = join(sounds: [FFmpeg.SegmentSound(system: nil, microphone: nil), FFmpeg.SegmentSound(system: nil, microphone: nil)])
    #expect(none.runs == [["-v", "error", "-nostdin", "-f", "concat", "-safe", "0", "-i", "/s/list.txt", "-map", "0:v", "-c", "copy", "-f", "mp4", "-y", "/r/out.mp4"]])
}

@Test func secondsArePrintedPlainly() {
    #expect(FFmpeg.seconds(0) == "0")
    #expect(FFmpeg.seconds(-0.0000001) == "0")
    #expect(FFmpeg.seconds(0.00001) == "0.00001")
    #expect(FFmpeg.seconds(12.5) == "12.5")
    #expect(FFmpeg.seconds(1.0 / 3) == "0.333333")
}
