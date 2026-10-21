import Foundation

extension FFmpeg {
    /// The rectangle of the X server's root window, in its pixels, that `x11grab` records for `area`, in points from the
    /// top left of the display at `origin` in the root: the part of it on the root, `root` big, rounded out to whole pixels
    /// and then down to an even width and height, which H.264's 4:2:0 needs. `nil` when less than 2 × 2 pixels of it are
    /// on the root.
    public static func grabArea(_ area: CGRect, origin: CGPoint, root: CGSize) -> CGRect? {
        let onRoot = area.offsetBy(dx: origin.x, dy: origin.y).integral.intersection(CGRect(origin: .zero, size: root))
        guard !onRoot.isNull else {
            return nil
        }
        let width = Int(onRoot.width) / 2 * 2, height = Int(onRoot.height) / 2 * 2
        guard width >= 2, height >= 2 else {
            return nil
        }
        return CGRect(x: onRoot.minX, y: onRoot.minY, width: Double(width), height: Double(height))
    }

    /// `ffmpeg`'s arguments to record `area`, in pixels of the root window of the X server `display` names, at
    /// `frameRate`, with the pointer drawn when `showsCursor`, as H.264 MP4 at `output`, stopping by itself after `limit`
    /// seconds. It reports its progress on standard output ten times a second, which `Progress` reads, and stops,
    /// writing a whole file, when `q` comes on its standard input. The frames come as the screen changes and are
    /// repeated or dropped to a constant rate.
    public static func grabArguments(display: String, area: CGRect, frameRate: Int, showsCursor: Bool, limit: Double, output: String) -> [String] {
        // Not `quiet`, whose -nostdin would leave nothing to stop it with.
        ["-v", "error", "-nostats", "-stats_period", "0.1", "-progress", "pipe:1", "-f", "x11grab", "-framerate", "\(frameRate)",
         "-video_size", "\(Int(area.width))x\(Int(area.height))", "-draw_mouse", showsCursor ? "1" : "0", "-i", "\(display)+\(Int(area.minX)),\(Int(area.minY))", "-t", seconds(limit), "-r", "\(frameRate)",
         "-vf", "scale=out_color_matrix=bt709:out_range=tv"]
            + recordingOptions + colors + ["-movflags", "+faststart", "-f", "mp4", "-y", output]
    }

    /// The raw pixel layouts a screen cast's frames come in, as ffmpeg names them, in the order of `CPipeWireStream`'s
    /// `shot_pw_format`: BGRx, BGRA, RGBx and RGBA.
    public static let castPixelFormats = ["bgr0", "bgra", "rgb0", "rgba"]

    /// `ffmpeg`'s arguments to record the raw frames written to its standard input, `size` pixels in `pixelFormat`, as
    /// H.264 MP4 at `output`, keeping only `crop` of them, in pixels, when it's given, and stopping by itself after `limit`
    /// seconds. Each frame is stamped when it arrives and repeated or dropped to a constant `frameRate`. It reports its
    /// progress as `grabArguments` has it, and stops, writing a whole file, when its standard input closes. `version` is
    /// ffmpeg's.
    public static func castArguments(
        size: CGSize, pixelFormat: String, crop: CGRect?, frameRate: Int, limit: Double, output: String, version: String? = nil
    ) -> [String] {
        let cropping = crop.map { "crop=\(Int($0.width)):\(Int($0.height)):\(Int($0.minX)):\(Int($0.minY))," } ?? ""
        return ["-v", "error", "-nostdin", "-nostats", "-stats_period", "0.1", "-progress", "pipe:1", "-use_wallclock_as_timestamps", "1",
                "-f", "rawvideo", "-pix_fmt", pixelFormat, "-video_size", "\(Int(size.width))x\(Int(size.height))", "-framerate", "\(frameRate)",
                "-i", "pipe:0", "-t", seconds(limit), "-vf", cropping + "scale=out_color_matrix=bt709:out_range=tv"]
            + frameMode("cfr", version: version) + ["-r", "\(frameRate)"]
            + recordingOptions + colors + ["-movflags", "+faststart", "-f", "mp4", "-y", output]
    }

    /// How Shot encodes H.264 as it records: quickly enough to keep up with the screen, with no frames held back, so a
    /// stop writes the last of them at once.
    static let recordingOptions = ["-c:v", h264Encoder, "-preset", "veryfast", "-tune", "zerolatency", "-crf", "20", "-pix_fmt", "yuv420p"]

    /// What ffmpeg writes on its standard input to stop recording.
    public static let stopKey = Data("q".utf8)

    /// What ffmpeg's `-progress` reports say, read as they come.
    public struct Progress: Equatable, Sendable {
        /// How many seconds it had recorded at its last whole report with a time; `nil` before one.
        public private(set) var recorded: Double?
        /// The end of what's been read that isn't a whole line yet.
        private var pending = ""
        /// The time in the report being read.
        private var time: Double?

        public init() {}

        /// Whether it has recorded anything yet.
        public var hasStarted: Bool { (recorded ?? 0) > 0 }

        public mutating func read(_ data: Data) {
            pending += String(decoding: data, as: UTF8.self)
            var lines = pending.split(separator: "\n", omittingEmptySubsequences: false)
            pending = String(lines.removeLast())
            for line in lines {
                if line.hasPrefix("out_time_us=") {
                    // N/A until it has a frame.
                    time = Double(line.dropFirst("out_time_us=".count)).flatMap { $0 >= 0 ? $0 / 1_000_000 : nil }
                } else if line.hasPrefix("progress=") {
                    recorded = time ?? recorded
                    time = nil
                }
            }
        }
    }
}
