import Foundation

/// One edit of a video, as `shot edit` and the MCP `edit_video` tool take it: the video editor's changes and its export,
/// as JSON. It's checked here, with no file access, so every field is tested; `ShotCommands` applies it to a
/// `Project`. Times are seconds of the input file, or `m:ss` text, and positions are its pixels, top-left origin.
public struct VideoEdit: Equatable, Sendable {
    /// The parts to keep, each `[start, end]`, in order; what's between and around them is cut.
    public var keep: [[Double]]
    /// The parts to cut, each `[start, end]`.
    public var cut: [[Double]]
    /// How fast it plays, as the export bar's speed does.
    public var speed: Double?
    /// Leaves out the sound.
    public var mute: Bool
    /// The part of the picture to keep, `[x, y, width, height]`.
    public var crop: [Double]?
    /// Marks shown over the video, each from `start` to `end`.
    public var marks: [TimedMark]
    /// Videos to play after it, in order.
    public var append: [String]
    public var format: Format?
    /// The most the file may be: a GIF steps down its frame rate and width to fit, and an MP4 its size.
    public var maxBytes: Int?
    /// A GIF's frames per second.
    public var fps: Double?
    /// A GIF's width at most, in pixels; 0 keeps the video's.
    public var width: Int?

    /// A mark in the capture record's format, shown from `start` to `end` seconds of the input.
    public struct TimedMark: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var mark: CaptureMark

        public init(start: Double, end: Double, mark: CaptureMark) {
            self.start = start
            self.end = end
            self.mark = mark
        }
    }

    public enum Format: String, Equatable, Sendable {
        case mp4, mov, gif
    }

    public init(
        keep: [[Double]] = [], cut: [[Double]] = [], speed: Double? = nil, mute: Bool = false, crop: [Double]? = nil, marks: [TimedMark] = [],
        append: [String] = [], format: Format? = nil, maxBytes: Int? = nil, fps: Double? = nil, width: Int? = nil
    ) {
        self.keep = keep
        self.cut = cut
        self.speed = speed
        self.mute = mute
        self.crop = crop
        self.marks = marks
        self.append = append
        self.format = format
        self.maxBytes = maxBytes
        self.fps = fps
        self.width = width
    }

    public static let fields = ["keep", "cut", "speed", "mute", "crop", "marks", "append", "format", "maxBytes", "fps", "width"]
    /// The speeds a video can play at.
    public static let speeds: ClosedRange<Double> = 0.25...4
    /// How long a mark shows when it gives no `end`, as one added in the editor does.
    public static let defaultMarkDuration: Double = 3
    /// The smallest `maxBytes`, below which no GIF or video is worth having.
    public static let minimumBytes = 10_000

    /// Whether it changes nothing.
    public var isEmpty: Bool { self == VideoEdit() }

    // MARK: Timing

    /// The parts of a `duration`-second input that `keep` or `cut` take out, in order, merged and within it. `nil` when
    /// a range starts at or past the end, with the field that does.
    public func removed(from duration: Double) throws(ShotCommandError) -> [Range<Double>] {
        let field = keep.isEmpty ? "cut" : "keep"
        for (index, range) in (keep.isEmpty ? cut : keep).enumerated() where range[0] >= duration {
            throw .data("\(field)[\(index)] starts at \(Self.format(range[0])) s, past the end of the \(String(format: "%.2f", duration)) s video")
        }
        var ranges: [Range<Double>]
        if keep.isEmpty {
            ranges = cut.map { $0[0]..<min($0[1], duration) }
        } else {
            let bounds = [0.0] + keep.flatMap { [$0[0], min($0[1], duration)] } + [duration]
            ranges = stride(from: 0, to: bounds.count, by: 2).map { bounds[$0]..<max(bounds[$0], bounds[$0 + 1]) }
        }
        var merged: [Range<Double>] = []
        for range in ranges.filter({ !$0.isEmpty }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Where `time` of the input plays once `removed` is taken out: earlier by everything removed before it, or where the
    /// video resumes if it was removed itself.
    public static func time(_ time: Double, after removed: [Range<Double>]) -> Double {
        removed.reduce(time) { shifted, range in
            guard range.lowerBound < time else { return shifted }
            return shifted - (min(time, range.upperBound) - range.lowerBound)
        }
    }

    // MARK: Parsing

    /// An edit from JSON. The first problem throws a `.data` error that names its field, such as `keep[1]`.
    public static func parse(_ data: Data) throws(ShotCommandError) -> VideoEdit {
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw .data("the edit isn't JSON: \(error.localizedDescription)")
        }
        return try parse(value)
    }

    /// An edit from a JSON object, as the MCP tool's arguments hold it, ignoring `ignoring`, such as the tool's `path`.
    public static func parse(_ value: JSONValue, ignoring: Set<String> = []) throws(ShotCommandError) -> VideoEdit {
        guard case let .object(object) = value else {
            throw .data("the edit must be a JSON object with any of \(ImageEdit.list(fields))")
        }
        for key in object.keys.sorted() where !fields.contains(key) && !ignoring.contains(key) {
            throw .data("unknown field \"\(key)\"; a video edit takes \(ImageEdit.list(fields))")
        }
        var edit = VideoEdit()
        let keep = present(object["keep"]), cut = present(object["cut"])
        if keep != nil, cut != nil {
            throw .data("use keep or cut, not both")
        }
        if let keep {
            edit.keep = try ranges(keep, field: "keep")
            for (index, pair) in zip(edit.keep, edit.keep.dropFirst()).enumerated() where pair.1[0] < pair.0[1] {
                throw .data("keep[\(index + 1)] starts before keep[\(index)] ends; give the parts in order, without overlaps")
            }
        }
        if let cut {
            edit.cut = try ranges(cut, field: "cut")
        }
        if let speed = present(object["speed"]) {
            guard case let .number(value) = speed, value.isFinite, speeds.contains(value) else {
                throw .data("speed must be a number from \(format(speeds.lowerBound)) to \(format(speeds.upperBound)), such as 2 for twice as fast")
            }
            edit.speed = value
        }
        if let mute = present(object["mute"]) {
            guard case let .bool(value) = mute else {
                throw .data("mute must be true or false")
            }
            edit.mute = value
        }
        if let crop = present(object["crop"]) {
            guard case let .array(items) = crop, items.count == 4 else {
                throw .data("crop must be [x, y, width, height] in the video's pixels, with a width and height above 0")
            }
            let rect = items.compactMap { item -> Double? in if case let .number(n) = item, n.isFinite { n } else { nil } }
            guard rect.count == 4, rect[2] > 0, rect[3] > 0 else {
                throw .data("crop must be [x, y, width, height] in the video's pixels, with a width and height above 0")
            }
            edit.crop = rect
        }
        if let marks = present(object["marks"]) {
            guard case let .array(items) = marks else {
                throw .data("marks must be an array of marks, each with a start, an end and the capture record's mark fields")
            }
            edit.marks = try items.enumerated().map { (index: Int, item: JSONValue) throws(ShotCommandError) -> TimedMark in
                try timedMark(item, field: "marks[\(index)]")
            }
        }
        if let append = present(object["append"]) {
            guard case let .array(items) = append else {
                throw .data("append must be an array of videos to play after it")
            }
            for (index, item) in items.enumerated() {
                guard let path = item.string, !path.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw .data("append[\(index)] must name a video")
                }
                edit.append.append(path)
            }
        }
        if let format = present(object["format"]) {
            guard let picked = format.string.flatMap({ Format(rawValue: $0.lowercased()) }) else {
                throw .data("format must be mp4, mov or gif")
            }
            edit.format = picked
        }
        if let maxBytes = present(object["maxBytes"]) {
            guard case let .number(value) = maxBytes, value.isFinite, value == value.rounded(), value >= Double(minimumBytes), value <= 1e12 else {
                throw .data("maxBytes must be a whole number of bytes, at least \(minimumBytes), such as 10000000 for 10 MB")
            }
            edit.maxBytes = Int(value)
        }
        if let fps = present(object["fps"]) {
            guard case let .number(value) = fps, value.isFinite, (1...30).contains(value) else {
                throw .data("fps must be a number from 1 to 30")
            }
            edit.fps = value
        }
        if let width = present(object["width"]) {
            guard case let .number(value) = width, value == value.rounded(), value == 0 || (16...8192).contains(value) else {
                throw .data("width must be from 16 to 8192 pixels, or 0 for the video's own width")
            }
            edit.width = Int(value)
        }
        if edit.format != .gif, edit.fps != nil || edit.width != nil {
            throw .data("\(edit.fps != nil ? "fps" : "width") is for a GIF; add \"format\": \"gif\"")
        }
        guard !edit.isEmpty else {
            throw .data("the edit changes nothing; give at least one of \(ImageEdit.list(fields))")
        }
        return edit
    }

    private static func ranges(_ value: JSONValue, field: String) throws(ShotCommandError) -> [[Double]] {
        guard case let .array(items) = value, !items.isEmpty else {
            throw .data("\(field) must be an array of [start, end] in seconds, such as [[2, 9.5]]")
        }
        return try items.enumerated().map { (index: Int, item: JSONValue) throws(ShotCommandError) -> [Double] in
            guard case let .array(pair) = item, pair.count == 2, let start = seconds(pair[0]), let end = seconds(pair[1]) else {
                throw .data("\(field)[\(index)] must be [start, end] in seconds, such as [2, 9.5] or [\"0:02\", \"1:10\"]")
            }
            guard end > start else {
                throw .data("\(field)[\(index)] must end after it starts")
            }
            return [start, end]
        }
    }

    private static func timedMark(_ value: JSONValue, field: String) throws(ShotCommandError) -> TimedMark {
        guard case var .object(object) = value else {
            throw .data("\(field) must be a mark, with a start, an end and the capture record's mark fields")
        }
        guard let startValue = present(object["start"]) else {
            throw .data("\(field) needs start, the second it shows from")
        }
        guard let start = seconds(startValue) else {
            throw .data("\(field).start must be seconds, such as 2.5, or m:ss, such as \"1:02.5\"")
        }
        var end = start + defaultMarkDuration
        if let endValue = present(object["end"]) {
            guard let given = seconds(endValue), given > start else {
                throw .data("\(field).end must be seconds after its start")
            }
            end = given
        }
        object["start"] = nil
        object["end"] = nil
        let mark: CaptureMark
        do {
            mark = try JSONDecoder().decode(CaptureMark.self, from: JSONEncoder().encode(JSONValue.object(object)))
        } catch {
            throw .data("\(field) isn't a mark: it needs a type, and its fields must be the record's")
        }
        if let problem = mark.problem {
            throw .data("\(field) (\(mark.type)): \(problem)")
        }
        return TimedMark(start: start, end: end, mark: mark)
    }

    /// Seconds from a number or `m:ss` text, as the command line reads times.
    private static func seconds(_ value: JSONValue) -> Double? {
        switch value {
        case let .number(number): number.isFinite && number >= 0 ? number : nil
        case let .string(text): ShotCommand.seconds(text.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    private static func present(_ value: JSONValue?) -> JSONValue? {
        value == .null ? nil : value
    }

    private static func format(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

/// The steps `maxBytes` tries, best first, so the first that fits loses the least.
public enum SizeFit {
    /// A GIF's frame rate and width: the frame rate drops before the width does, since a smaller GIF is harder to read
    /// than a less smooth one. `width` is the one asked for, or the video's own, never enlarged.
    public struct GIFStep: Equatable, Sendable {
        public var fps: Double
        public var width: Int

        public init(fps: Double, width: Int) {
            self.fps = fps
            self.width = width
        }
    }

    public static let gifRates: [Double] = [15, 12, 10, 8, 6]
    public static let gifWidths = [1080, 960, 720, 640, 480, 400, 320]

    public static func gifSteps(fps: Double, width: Int) -> [GIFStep] {
        let rates = [fps] + gifRates.filter { $0 < fps }
        let widths = [width] + gifWidths.filter { $0 < width }
        return widths.flatMap { width in rates.map { GIFStep(fps: $0, width: width) } }
    }

    /// The fractions of the canvas an MP4 is drawn at, largest first.
    public static let videoScales: [Double] = [1, 0.75, 0.5, 0.375, 0.25]

    /// Whether a step estimated at `estimate` bytes should fit in `maxBytes`, with a tenth to spare since estimates are
    /// rough. `ratio` is how far over its estimate a step already written came out, which the rest are corrected by.
    public static func fits(estimate: Int, ratio: Double, within maxBytes: Int) -> Bool {
        Double(estimate) * ratio <= Double(maxBytes) * 0.9
    }
}
