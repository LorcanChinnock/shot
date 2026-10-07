import Foundation

public enum Snapping {
    /// How close, in points, a time has to be to a snap point to jump to it.
    public static let reach: CGFloat = 8

    /// The nearest of `points` within `threshold` of `time`; nil when none is.
    public static func snap(_ time: Double, to points: [Double], within threshold: Double) -> Double? {
        points.filter { abs($0 - time) <= threshold }.min { abs($0 - time) < abs($1 - time) }
    }
}

/// How far the lanes are zoomed in: 1 fits the whole project in the window.
public enum TimelineZoom {
    public static let range: ClosedRange<Double> = 1...64
    static let step = 1.5

    public static func zoomed(_ zoom: Double, bySteps steps: Int) -> Double {
        min(max(zoom * pow(step, Double(steps)), range.lowerBound), range.upperBound)
    }

    /// The zoom that keeps `time` under the same x after the change: the scroll offset to use, in points.
    public static func offset(keeping time: Double, atViewX viewX: CGFloat, duration: Double, zoom: Double, viewWidth: CGFloat) -> CGFloat {
        guard duration > 0 else {
            return 0
        }
        let contentWidth = viewWidth * CGFloat(zoom)
        let offset = contentWidth * CGFloat(time / duration) - viewX
        return min(max(offset, 0), max(0, contentWidth - viewWidth))
    }
}

public enum TimelineRuler {
    private static let intervals: [Double] = [0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]

    /// The smallest round number of seconds between labels that keeps them `minSpacing` points apart.
    public static func interval(pointsPerSecond: CGFloat, minSpacing: CGFloat = 64) -> Double {
        guard pointsPerSecond > 0 else {
            return intervals.last!
        }
        return intervals.first { Double(pointsPerSecond) * $0 >= Double(minSpacing) } ?? intervals.last!
    }

    /// Labelled times from 0 up to `duration`.
    public static func ticks(duration: Double, interval: Double) -> [Double] {
        guard duration > 0, interval > 0 else {
            return []
        }
        return (0...Int((duration / interval).rounded(.down))).map { Double($0) * interval }
    }

    /// `1:05`, or `0:01.5` when the labels are closer than a second.
    public static func label(_ seconds: Double, interval: Double) -> String {
        let hundredths = Int((seconds * 100).rounded())
        let whole = hundredths / 100
        let base = "\(whole / 60):" + String(format: "%02d", whole % 60)
        return interval < 1 ? base + String(format: ".%d", hundredths % 100 / 10) : base
    }
}

/// Where each track's lane sits in the panel, top to bottom: the annotation tracks, then the picture tracks above the main one,
/// each top-most first, then the main track, then the sound tracks.
public struct LaneLayout: Equatable, Sendable {
    public struct Lane: Equatable, Sendable {
        public var track: Int
        public var y: CGFloat
        public var height: CGFloat
    }

    public static let mainHeight: CGFloat = 56
    public static let annotationHeight: CGFloat = 28
    public static let pictureHeight: CGFloat = 40
    public static let soundHeight: CGFloat = 40
    public static let gap: CGFloat = 4

    public let lanes: [Lane]
    public let height: CGFloat

    /// Lanes start `top` points down, below the ruler.
    public init(_ project: Project, top: CGFloat) {
        var lanes: [Lane] = []
        var y = top
        func add(_ track: Int, _ height: CGFloat) {
            lanes.append(Lane(track: track, y: y, height: height))
            y += height + Self.gap
        }
        for index in project.tracks.indices.reversed() where project.tracks[index].kind == .overlay {
            add(index, Self.annotationHeight)
        }
        for index in project.tracks.indices.reversed() where index != 0 && project.tracks[index].kind == .video {
            add(index, Self.pictureHeight)
        }
        add(0, Self.mainHeight)
        for index in project.tracks.indices where project.tracks[index].kind == .audio {
            add(index, Self.soundHeight)
        }
        self.lanes = lanes
        height = y - Self.gap
    }

    /// How tall the panel may be when only `available` points are left for it: the lanes scroll rather than squeeze the preview,
    /// but never below `minimum`, which keeps the ruler and the main lane in view.
    public func visibleHeight(available: CGFloat, minimum: CGFloat) -> CGFloat {
        min(height, max(available, minimum))
    }

    public func lane(at y: CGFloat) -> Lane? {
        lanes.first { y >= $0.y && y < $0.y + $0.height }
    }

    public func lane(ofTrack track: Int) -> Lane? {
        lanes.first { $0.track == track }
    }
}

extension Project {
    /// How much was trimmed off the front of the main track, which the lanes leave room for before time 0.
    public var trimmedLead: Double { main.clips.first?.sourceStart ?? 0 }

    /// The trimmed-off ends of the clips in track `index`, as far as they reach into empty space and no further back than
    /// `trimmedLead` before 0, each as the clip narrowed to that stretch and placed where it would play.
    public func trimmedEnds(ofTrack index: Int) -> [Clip] {
        let clips = tracks[index].clips.sorted { $0.start < $1.start }
        var ends: [Clip] = []
        for (position, clip) in clips.enumerated() {
            let before = position > 0 ? clips[position - 1].end : -trimmedLead
            let after = position + 1 < clips.count ? clips[position + 1].start : .infinity
            let head = min(clip.sourceStart, clip.start - before)
            if head > Self.shortestClip {
                var end = clip
                end.sourceStart -= head
                end.sourceEnd = clip.sourceStart
                end.start -= head
                ends.append(end)
            }
            let tail = min(clip.sourceDuration - clip.sourceEnd, after - clip.end)
            if tail > Self.shortestClip {
                var end = clip
                end.sourceStart = clip.sourceEnd
                end.sourceEnd += tail
                end.start = clip.end
                ends.append(end)
            }
        }
        return ends
    }

    /// Where on the timeline the main track jumps over a cut section of the same file.
    public var mainCuts: [Double] {
        zip(main.clips, main.clips.dropFirst()).compactMap { previous, next in
            next.source == previous.source && abs(next.sourceStart - previous.sourceEnd) > Self.shortestClip ? next.start : nil
        }
    }
}
