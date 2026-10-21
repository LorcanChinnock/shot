import Foundation

/// A labelled moment in a recording, stamped by an agent with `shot record --mark` or `record_window`'s mark action, so
/// the key frames show what the agent was doing then. `time` is seconds into the saved video, pauses left out.
public struct RecordingMark: Codable, Equatable, Sendable {
    /// The longest label, in characters.
    public static let maximumLabel = 200
    /// The most marks one recording keeps.
    public static let maximumCount = 100

    public var time: Double
    public var label: String

    public init(time: Double, label: String) {
        self.time = time
        self.label = label
    }

    /// A frame to show of a recording: its time, and the labels of the marks there, if any.
    public struct KeyFrame: Equatable, Sendable {
        public var time: Double
        public var labels: [String]

        public init(time: Double, labels: [String] = []) {
            self.time = time
            self.labels = labels
        }
    }

    /// The frames `marks` ask for in a video `duration` long: one per moment, with marks closer than `near` sharing
    /// one, each within the video. At most `limit - 2`, the earliest, so the first and last frames still fit.
    public static func frames(for marks: [RecordingMark], duration: Double, limit: Int, near: Double = 0.25) -> [KeyFrame] {
        // The last frame the extractor can decode, as `KeyFrameExtractor` takes it.
        let last = max(0, duration - 0.05)
        var frames: [KeyFrame] = []
        for mark in marks.sorted(by: { $0.time < $1.time }) where mark.time.isFinite {
            let time = min(max(mark.time, 0), last)
            if let previous = frames.last, time - previous.time < near {
                frames[frames.count - 1].labels.append(mark.label)
            } else {
                frames.append(KeyFrame(time: time, labels: [mark.label]))
            }
        }
        return Array(frames.prefix(max(0, limit - 2)))
    }

    /// How many frames where the picture changes to show beside `marked` frames of marks: `count`, fewer when that
    /// would go over `limit`, and never fewer than the first and last.
    public static func changeCount(_ count: Int, marked: Int, limit: Int) -> Int {
        max(2, min(count, limit - marked))
    }

    /// `changes`, the times `FramePicker` picked, and `marked` together in time order. A change closer than `near` to a
    /// mark's frame is left out, since it would show the same picture.
    public static func merge(changes: [Double], marked: [KeyFrame], near: Double = 0.25) -> [KeyFrame] {
        let unmarked = changes.filter { change in !marked.contains { abs($0.time - change) < near } }
        return (marked + unmarked.map { KeyFrame(time: $0) }).sorted { $0.time < $1.time }
    }
}
