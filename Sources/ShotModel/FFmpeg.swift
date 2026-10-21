import Foundation

/// The arguments Shot runs the `ffmpeg` and `ffprobe` programs with, and what it reads from what they print, kept apart
/// from running them so they're tested anywhere. ShotCoreLinux's `FFmpegReader` and `FFmpegAssembler` run them.
///
/// Times Shot asks for start at 0 when the file starts. Times in the file can start later, so the times ffprobe prints
/// are moved back by the file's start time, and moved on again where ffmpeg is asked for them.
public enum FFmpeg {
    // MARK: Finding the programs

    /// Where to run `name` from: `override`, the value of `SHOT_FFMPEG` or `SHOT_FFPROBE`, when it names a program,
    /// else the first folder of `path`, a `PATH`, that holds one.
    public static func locate(_ name: String, override: String?, path: String?, isExecutable: (String) -> Bool) -> String? {
        if let override, !override.isEmpty, isExecutable(override) {
            return override
        }
        for folder in (path ?? "").split(separator: ":") where !folder.isEmpty {
            let candidate = folder.hasSuffix("/") ? "\(folder)\(name)" : "\(folder)/\(name)"
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// The version `ffmpeg -version` names on its first line, such as `6.1.1-3ubuntu5`.
    public static func version(from output: String) -> String? {
        guard let line = output.split(whereSeparator: \.isNewline).first else {
            return nil
        }
        let words = line.split(separator: " ")
        guard let index = words.firstIndex(of: "version"), index + 1 < words.count else {
            return nil
        }
        return String(words[index + 1])
    }

    /// The encoders `ffmpeg -hide_banner -encoders` lists, such as `libx264`, from the lines after its legend.
    public static func encoders(from output: String) -> Set<String> {
        var names = Set<String>()
        var listed = false
        for line in output.split(whereSeparator: \.isNewline) {
            let words = line.split(separator: " ")
            if !listed {
                listed = words.first?.allSatisfy { $0 == "-" } == true
                continue
            }
            if words.count >= 2 {
                names.insert(String(words[1]))
            }
        }
        return names
    }

    /// How to install the programs, for an error or `shot doctor` that can't find them.
    public static let install = "Install ffmpeg (sudo apt install ffmpeg on Debian and Ubuntu), or set SHOT_FFMPEG and SHOT_FFPROBE to where they are."

    /// The encoder Shot makes H.264 with, when it can't copy the video.
    public static let h264Encoder = "libx264"
    /// The encoder Shot makes HEVC with, when it's asked for.
    public static let hevcEncoder = "libx265"

    // MARK: Probing

    static let quiet = ["-v", "error", "-nostdin"]

    /// `ffprobe`'s arguments to describe `file`'s streams and container as JSON, which `Probe` reads.
    public static func probeArguments(_ file: String) -> [String] {
        ["-v", "error", "-show_streams", "-show_format", "-of", "json", file]
    }

    /// What `ffprobe` says of a file, as `probeArguments` ask for it.
    public struct Probe: Decodable, Sendable {
        public struct Stream: Decodable, Sendable {
            public var codecType: String?
            /// Such as `h264` or `aac`.
            public var codecName: String?
            public var width: Int?
            public var height: Int?
            public var bitRate: String?
            public var sideData: [[String: SideDataValue]]?
            public var tags: [String: String]?
            public var disposition: [String: Int]?

            private enum CodingKeys: String, CodingKey {
                case codecType = "codec_type", codecName = "codec_name", width, height, bitRate = "bit_rate", sideData = "side_data_list", tags, disposition
            }

            /// Whether it's a picture, rather than a cover image an audio file carries.
            var isVideo: Bool { codecType == "video" && disposition?["attached_pic"] != 1 }

            /// How far it's turned, in degrees, from its display matrix or, from older files, its `rotate` tag.
            var rotation: Double {
                sideData?.compactMap { $0["rotation"]?.value }.first ?? tags?["rotate"].flatMap(Double.init) ?? 0
            }

            /// Its bit rate, or the one Matroska keeps in a tag.
            var bitsPerSecond: Double? {
                bitRate.flatMap(Double.init) ?? tags?["BPS"].flatMap(Double.init)
            }
        }

        public struct Format: Decodable, Sendable {
            public var duration: String?
            public var startTime: String?
            public var bitRate: String?

            private enum CodingKeys: String, CodingKey {
                case duration, startTime = "start_time", bitRate = "bit_rate"
            }
        }

        /// A side data field, which ffprobe prints as a number or a string.
        public struct SideDataValue: Decodable, Sendable {
            public var value: Double?

            public init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                value = (try? container.decode(Double.self)) ?? (try? container.decode(String.self)).flatMap(Double.init)
            }
        }

        public var streams: [Stream]
        public var format: Format

        public init(json: Data) throws {
            self = try JSONDecoder().decode(Probe.self, from: json)
        }

        /// How long it plays, in seconds; 0 when ffprobe can't say.
        public var duration: Double { format.duration.flatMap(Double.init) ?? 0 }
        /// When the file starts, in seconds of its own times.
        public var startTime: Double { format.startTime.flatMap(Double.init) ?? 0 }
        public var hasVideo: Bool { streams.contains(where: \.isVideo) }
        public var hasAudio: Bool { streams.contains { $0.codecType == "audio" } }

        /// The size of its first video stream's picture as it plays, turned as its display matrix says; `nil` without one.
        public var size: CGSize? {
            guard let video = streams.first(where: \.isVideo), let width = video.width, let height = video.height else {
                return nil
            }
            let turned = Int(abs(video.rotation.rounded())) % 180 == 90
            return turned ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        }

        /// The bit rates of its video streams and of its audio streams, each summed, in bits a second. A video stream that
        /// doesn't say has whatever of the file's rate the audio leaves.
        public var bitRates: (video: Double, audio: Double) {
            let audio = streams.filter { $0.codecType == "audio" }.compactMap(\.bitsPerSecond).reduce(0, +)
            let videos = streams.filter(\.isVideo)
            var video = videos.compactMap(\.bitsPerSecond).reduce(0, +)
            if video == 0, !videos.isEmpty, let total = format.bitRate.flatMap(Double.init) {
                video = max(0, total - audio)
            }
            return (video, audio)
        }
    }

    /// `ffprobe`'s arguments to list when each packet of `file`'s first video stream is shown and whether it's a sync
    /// frame, without decoding it, and when the file starts; `VideoPackets` reads them.
    public static func packetArguments(_ file: String) -> [String] {
        ["-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time,flags:format=start_time", "-of", "compact", file]
    }

    /// The frames of a file's first video stream, as `packetArguments` list them.
    public struct VideoPackets: Equatable, Sendable {
        /// When each frame is shown, in order, in seconds from the start of the file.
        public var times: [Double]
        /// Whether each of `times` is a sync frame, which decodes on its own.
        public var isSync: [Bool]
        /// When the file starts, in seconds of its own times.
        public var startTime: Double

        public init(times: [Double], isSync: [Bool], startTime: Double = 0) {
            self.times = times
            self.isSync = isSync
            self.startTime = startTime
        }

        /// Reads `ffprobe -of compact`'s lines, such as `packet|pts_time=0.033333|flags=K__`. Packets with no time, or
        /// that the file says to drop, aren't shown.
        public init(compact output: String) {
            var packets: [(time: Double, sync: Bool)] = []
            var start = 0.0
            for line in output.split(whereSeparator: \.isNewline) {
                var fields: [Substring: Substring] = [:]
                let parts = line.split(separator: "|")
                for part in parts.dropFirst() {
                    if let equals = part.firstIndex(of: "=") {
                        fields[part[..<equals]] = part[part.index(after: equals)...]
                    }
                }
                switch parts.first {
                case "packet":
                    let flags = fields["flags"] ?? ""
                    if let time = fields["pts_time"].flatMap({ Double($0) }), !flags.contains("D") {
                        packets.append((time, flags.contains("K")))
                    }
                case "format":
                    start = fields["start_time"].flatMap { Double($0) } ?? 0
                default:
                    break
                }
            }
            packets.sort { $0.time < $1.time }
            self.init(times: packets.map { $0.time - start }, isSync: packets.map(\.sync), startTime: start)
        }

        /// When the sync frames are shown.
        public var syncTimes: [Double] { zip(times, isSync).filter(\.1).map(\.0) }

        /// When the sync frame at or before `time` is shown, or `time` itself when there's none.
        public func syncTime(atOrBefore time: Double) -> Double {
            syncTimes.last { $0 <= time + epsilon } ?? time
        }

        /// The frame to decode for `time`: the nearest sync frame when it's within `tolerance` either side, since it decodes
        /// fastest, else the frame shown at `time`. A `nil` tolerance takes the nearest sync frame wherever it is.
        public func frame(at time: Double, tolerance: Double?) -> Int? {
            guard !times.isEmpty else {
                return nil
            }
            let sync = times.indices.filter { isSync[$0] }.min { abs(times[$0] - time) < abs(times[$1] - time) }
            if let sync, abs(times[sync] - time) <= (tolerance ?? .infinity) + epsilon {
                return sync
            }
            return times.lastIndex { $0 <= time + epsilon } ?? 0
        }

        /// `frames`, sorted, in runs that each decode from one seek: a frame starts a new run when the sync frame it decodes
        /// from comes more than `gap` seconds after the frame before it, so seeking there skips that much decoding.
        public func runs(of frames: [Int], gap: Double = 2) -> [[Int]] {
            var runs: [[Int]] = []
            for frame in Set(frames).sorted() {
                if let last = runs.last?.last, syncTime(atOrBefore: times[frame]) - times[last] <= gap {
                    runs[runs.count - 1].append(frame)
                } else {
                    runs.append([frame])
                }
            }
            return runs
        }
    }

    /// How close two times must be to count as the same frame's, since ffprobe prints them to the microsecond.
    static let epsilon = 0.0005

    // MARK: Reading

    /// The size a frame of `size` is decoded at to fit `maximum`, where 0 leaves a side free, keeping its shape and never
    /// enlarging it.
    public static func fitted(_ size: CGSize, within maximum: CGSize) -> (width: Int, height: Int) {
        var scale = 1.0
        if maximum.width > 0 {
            scale = min(scale, maximum.width / size.width)
        }
        if maximum.height > 0 {
            scale = min(scale, maximum.height / size.height)
        }
        return (max(1, Int((size.width * scale).rounded())), max(1, Int((size.height * scale).rounded())))
    }

    /// The option that has ffmpeg hand frames on as they come, where raw video would otherwise repeat them to a constant
    /// rate: `-fps_mode` from ffmpeg 5.1, the only one ffmpeg 9 takes, and `-vsync` before it. A version that doesn't
    /// start with one, such as a build from git, is taken to be new.
    public static func passthrough(version: String?) -> [String] {
        let numbers = (version ?? "").drop { $0 == "n" }.split(separator: ".").prefix(2).map { Int($0.prefix { $0.isNumber }) }
        guard let major = numbers.first ?? nil else {
            return ["-fps_mode", "passthrough"]
        }
        let minor = numbers.count > 1 ? numbers[1] ?? 0 : 0
        return (major, minor) < (5, 1) ? ["-vsync", "passthrough"] : ["-fps_mode", "passthrough"]
    }

    /// `ffmpeg`'s arguments to decode `frames` of `packets`, one run of `VideoPackets.runs`, from `file`, upright, as
    /// `width` × `height` RGBA, one after another in time order, with nothing between them. It seeks to the sync frame
    /// before the first and picks the frames by when they're shown, in the file's own times. `version` is ffmpeg's.
    public static func frameArguments(_ file: String, frames: [Int], of packets: VideoPackets, width: Int, height: Int, version: String? = nil) -> [String] {
        let seek = frames.first.map { packets.times[$0] } ?? 0
        let picked = frames.map { index in
            let time = packets.times[index] + packets.startTime
            return "between(t,\(seconds(time - epsilon)),\(seconds(time + epsilon)))"
        }
        return quiet + (seek > 0 ? ["-noaccurate_seek", "-ss", seconds(seek)] : []) + [
            "-copyts", "-i", file, "-map", "0:v:0", "-vf", "select='\(picked.joined(separator: "+"))',scale=\(width):\(height)",
        ] + passthrough(version: version) + ["-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"]
    }

    /// `ffmpeg`'s arguments to decode `file`'s first audio stream as mono 32-bit float samples at `sampleRate`, for
    /// `duration` seconds when it's given, which leaves out the padding an encoder adds at the end.
    public static func sampleArguments(_ file: String, sampleRate: Double, duration: Double? = nil) -> [String] {
        quiet + ["-i", file, "-map", "0:a:0"] + (duration.map { ["-t", seconds($0)] } ?? [])
            + ["-ac", "1", "-ar", "\(Int(sampleRate.rounded()))", "-f", "f32le", "pipe:1"]
    }

    // MARK: Trimming and joining

    /// The uniform type identifiers of the files Shot trims and joins, and the ffmpeg formats it writes them as.
    static let formats: [(type: String, extensions: [String], muxer: String)] = [
        ("public.mpeg-4", ["mp4"], "mp4"),
        ("com.apple.quicktime-movie", ["mov", "qt"], "mov"),
        ("com.apple.m4v-video", ["m4v"], "mp4"),
    ]

    /// The uniform type identifier of a video named with `pathExtension`, when it's one Shot writes.
    public static func fileType(forExtension pathExtension: String) -> String? {
        formats.first { $0.extensions.contains(pathExtension.lowercased()) }?.type
    }

    /// The ffmpeg format that writes `fileType`, a uniform type identifier, when it's one Shot writes.
    public static func muxer(for fileType: String) -> String? {
        formats.first { $0.type == fileType }?.muxer
    }

    /// The ffmpeg runs that make a file, in order, with the list of files the concat demuxer reads, if it's used.
    public struct Job: Equatable, Sendable {
        public var runs: [[String]]
        /// What `concatList` holds: a `file` line for each file it joins.
        public var concatList: String?
        /// Whether the video's copied as it is, rather than encoded again.
        public var copiesVideo: Bool
    }

    /// What `trim` needs to know of the file it trims.
    public struct Source: Sendable {
        public var path: String
        public var hasAudio: Bool

        public init(path: String, hasAudio: Bool) {
            self.path = path
            self.hasAudio = hasAudio
        }
    }

    /// The runs that write the `kept` sections of `source` end to end to `output` as `muxer`, at `speed`, without the
    /// sound when `muted`, keeping anything made on the way in `scratch`.
    ///
    /// Unless `copying` is false, one section is copied as it is from a seek before the input, which cuts it exactly with
    /// an edit list. A different speed copies it to `scratch` first and retimes the copy, since `-itsscale` would also
    /// stretch `-t`. Several sections are encoded again as H.264, and the sound with them as AAC, sped up with `atempo`
    /// keeping its pitch: copied through the concat demuxer, a section would keep the frames that decode after its end,
    /// which B-frames put there, and they'd overlap the next.
    public static func trim(
        _ source: Source, kept: [TrimRange], speed: Double, muted: Bool, to output: String, as muxer: String, scratch: String, copying: Bool = true
    ) -> Job {
        let sound = source.hasAudio && !muted
        let audioOut = ["-c:a", "aac", "-b:a", "160k"]
        let write = ["-f", muxer, "-y", output]
        guard copying, kept.count == 1, let section = kept.first else {
            return Job(runs: [quiet + ["-i", source.path] + encoded(kept, of: source, speed: speed, sound: sound) + (sound ? audioOut : []) + write], concatList: nil, copiesVideo: false)
        }
        let input = ["-ss", seconds(section.start), "-t", seconds(section.end - section.start), "-i", source.path]
        guard speed != 1 else {
            return Job(runs: [quiet + input + ["-map", "0:v"] + (sound ? ["-map", "0:a"] : []) + ["-c", "copy"] + write], concatList: nil, copiesVideo: true)
        }
        let video = "\(scratch)/video.mp4"
        let copy = quiet + input + ["-map", "0:v", "-c", "copy", "-f", "mp4", "-y", video]
        let retime = quiet + ["-itsscale", seconds(1 / speed), "-i", video] + (sound ? input : []) + ["-map", "0:v", "-c:v", "copy"]
            + (sound ? ["-map", "1:a", "-filter:a", tempo(speed)] + audioOut : []) + write
        return Job(runs: [copy, retime], concatList: nil, copiesVideo: true)
    }

    /// The filter graph and outputs that join `kept` of `source`'s first video stream, and of its first audio stream
    /// when there's `sound`, at `speed`, encoded again. Without `-copyts`, ffmpeg moves the input's times back by its start
    /// time, so the sections are cut at times from the start of the file, as Shot gives them.
    static func encoded(_ kept: [TrimRange], of source: Source, speed: Double, sound: Bool) -> [String] {
        var graph: [String] = []
        var joined = ""
        let split = kept.count > 1
        graph.append("[0:v:0]" + (split ? "split=\(kept.count)" + kept.indices.map { "[vs\($0)]" }.joined() : "null[vs0]"))
        if sound {
            graph.append("[0:a:0]" + (split ? "asplit=\(kept.count)" + kept.indices.map { "[as\($0)]" }.joined() : "anull[as0]"))
        }
        for (index, section) in kept.enumerated() {
            let range = "start=\(seconds(section.start)):end=\(seconds(section.end))"
            graph.append("[vs\(index)]trim=\(range),setpts=PTS-STARTPTS[v\(index)]")
            joined += "[v\(index)]"
            if sound {
                graph.append("[as\(index)]atrim=\(range),asetpts=PTS-STARTPTS[a\(index)]")
                joined += "[a\(index)]"
            }
        }
        graph.append(joined + "concat=n=\(kept.count):v=1:a=\(sound ? 1 : 0)[vc]" + (sound ? "[ac]" : ""))
        graph.append("[vc]" + (speed == 1 ? "null" : "setpts=PTS/\(seconds(speed))") + "[v]")
        if sound {
            graph.append("[ac]" + (speed == 1 ? "anull" : tempo(speed)) + "[a]")
        }
        return ["-filter_complex", graph.joined(separator: ";"), "-map", "[v]"] + (sound ? ["-map", "[a]"] : [])
            + ["-c:v", h264Encoder, "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"]
    }

    /// `atempo` filters that play sound `speed` times as fast, each within the half to double one filter takes.
    static func tempo(_ speed: Double) -> String {
        var factors: [Double] = []
        var left = speed
        while left > 2 {
            factors.append(2)
            left /= 2
        }
        while left < 0.5 {
            factors.append(0.5)
            left /= 0.5
        }
        factors.append(left)
        return factors.map { "atempo=\(seconds($0))" }.joined(separator: ",")
    }

    /// A segment's sound, recorded to files of its own: those of `system` and `microphone` that hold any.
    public struct SegmentSound: Equatable, Sendable {
        public var system: String?
        public var microphone: String?

        public init(system: String?, microphone: String?) {
            self.system = system
            self.microphone = microphone
        }
    }

    /// The run that joins `segments`, which play for `durations`, end to end at `output` as MP4, copying the video,
    /// with `concatList` listing them. Without `sounds`, the segments' own sound is copied, or encoded again silent
    /// over `muted` when `hasAudio`. With `sounds`, one per segment, the files in each are laid where the segment
    /// starts, cut to its length, and mixed, with only the microphone silent over `muted`.
    public static func concatenate(_ segments: [String], durations: [Double], sounds: [SegmentSound], hasAudio: Bool, muting muted: [Range<Double>], to output: String, concatList: String) -> Job {
        let list = segments.map { "file \(quoted($0))\n" }.joined()
        let input = quiet + ["-f", "concat", "-safe", "0", "-i", concatList]
        let write = ["-f", "mp4", "-y", output]
        let audioOut = ["-c:a", "aac", "-b:a", "160k"]
        let silence = "volume=0:enable='\(muted.map { "between(t,\(seconds($0.lowerBound)),\(seconds($0.upperBound)))" }.joined(separator: "+"))'"
        guard !sounds.isEmpty else {
            guard hasAudio, !muted.isEmpty else {
                return Job(runs: [input + ["-map", "0:v?", "-map", "0:a?", "-c", "copy"] + write], concatList: list, copiesVideo: true)
            }
            return Job(runs: [input + ["-map", "0:v", "-map", "0:a", "-c:v", "copy", "-filter:a", silence] + audioOut + write], concatList: list, copiesVideo: true)
        }
        var inputs: [String] = []
        var graph: [String] = []
        var mixed = ""
        var offset = 0.0
        for (duration, sound) in zip(durations, sounds) {
            for (file, isMicrophone) in [(sound.system, false), (sound.microphone, true)] {
                guard let file else {
                    continue
                }
                inputs += ["-i", file]
                let index = inputs.count / 2
                var chain = "[\(index):a:0]atrim=end=\(seconds(duration)),asetpts=PTS-STARTPTS,adelay=delays=\(Int((offset * 1000).rounded())):all=1"
                if isMicrophone, !muted.isEmpty {
                    chain += "," + silence
                }
                graph.append(chain + "[s\(index)]")
                mixed += "[s\(index)]"
            }
            offset += duration
        }
        guard !graph.isEmpty else {
            return Job(runs: [input + ["-map", "0:v", "-c", "copy"] + write], concatList: list, copiesVideo: true)
        }
        let count = inputs.count / 2
        graph.append(mixed + (count > 1 ? "amix=inputs=\(count):normalize=0:duration=longest," : "") + "atrim=end=\(seconds(offset))[a]")
        return Job(
            runs: [input + inputs + ["-filter_complex", graph.joined(separator: ";"), "-map", "0:v", "-c:v", "copy", "-map", "[a]"] + audioOut + write],
            concatList: list, copiesVideo: true
        )
    }

    // MARK: Formatting

    /// `value` as ffmpeg reads seconds, to the microsecond, never in exponent form.
    static func seconds(_ value: Double) -> String {
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text == "-0" ? "0" : text
    }

    /// `path` quoted for a concat list, where a quote ends the quoting and `\'` stands for one.
    static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
