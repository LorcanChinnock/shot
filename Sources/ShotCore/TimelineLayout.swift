import Foundation

/// Where each track's lane sits in the panel, top to bottom: the annotation and picture tracks above the main one, in the order
/// they're drawn, top-most first, then the main track, then the sound tracks.
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
        for index in project.stackedTrackIndices.reversed() {
            add(index, project.tracks[index].kind == .overlay ? Self.annotationHeight : Self.pictureHeight)
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

    /// The lane switches (lock, hide, mute): square buttons in a row, `controlInset` in from the view's left edge.
    public static let controlSize: CGFloat = 20
    public static let controlSpacing: CGFloat = 3
    public static let controlInset: CGFloat = 4

    /// How far from the view's left edge `count` lane switches reach; 0 when none show.
    public static func controlsWidth(count: Int) -> CGFloat {
        guard count > 0 else {
            return 0
        }
        return controlInset + CGFloat(count) * controlSize + CGFloat(count - 1) * controlSpacing
    }

    /// How much further in a clip's name starts so the lane switches don't cover it: the switches reach `controlsEnd` and the
    /// clip starts at `clipX`, both from the same origin. 0 when the clip starts past them.
    public static func labelInset(clipX: CGFloat, controlsEnd: CGFloat) -> CGFloat {
        max(0, controlsEnd - clipX)
    }

    /// How close to a lane's edge a clip dragged up or down drops between lanes, onto a new track of its own.
    public static let insertReach: CGFloat = 7

    /// Where a clip dragged to `y` lands among the lanes above the main one, which are `project`'s: onto the lane under it,
    /// or onto a new track near the edge between two lanes, above the top one, or anywhere below the bottom one.
    public func laneDrop(at y: CGFloat, in project: Project) -> LaneDrop? {
        let stacked = lanes.filter { $0.track != 0 && project.tracks[$0.track].kind != .audio }
        guard let top = stacked.first, let bottom = stacked.last else {
            return nil
        }
        if y < top.y + Self.insertReach {
            return .insert(top.track + 1)
        }
        for (upper, lower) in zip(stacked, stacked.dropFirst()) where y >= upper.y + upper.height - Self.insertReach && y < lower.y + Self.insertReach {
            return .insert(lower.track + 1)
        }
        if y >= bottom.y + bottom.height - Self.insertReach {
            return .insert(bottom.track)
        }
        return stacked.first { y >= $0.y && y < $0.y + $0.height }.map { .onto($0.track) }
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
