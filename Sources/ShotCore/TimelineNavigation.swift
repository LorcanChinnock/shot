import Foundation

/// Selecting on the video timeline from the keyboard, since every other way needs a drag: ⌥← and ⌥→ step through a lane's
/// clips, ⌥↑ and ⌥↓ move between lanes, and I and O mark the start and end of a range at the playhead.
public enum TimelineNavigation {
    /// A clip or annotation the keyboard can select, with where it starts on the timeline.
    public struct Target: Equatable, Sendable {
        public let id: UUID
        public let start: Double
    }

    /// How close to a clip's start the playhead counts as on it.
    static let tolerance = 0.001

    /// The track's clips, or an annotation track's annotations, in timeline order.
    static func items(onTrack track: Int, in project: Project) -> [(id: UUID, start: Double, end: Double)] {
        guard project.tracks.indices.contains(track) else {
            return []
        }
        let lane = project.tracks[track]
        let items = lane.clips.map { (id: $0.id, start: $0.start, end: $0.end) } + lane.annotations.map { (id: $0.id, start: $0.start, end: $0.end) }
        return items.sorted { $0.start < $1.start }
    }

    /// The clip before (`forward` false) or after the selected one on `track`, or, when nothing on that track is selected,
    /// the last one starting before the playhead or the first starting after it. Nil at either end.
    public static func step(forward: Bool, onTrack track: Int, in project: Project, selected: UUID?, playhead: Double) -> Target? {
        let items = items(onTrack: track, in: project)
        if let selected, let index = items.firstIndex(where: { $0.id == selected }) {
            let next = index + (forward ? 1 : -1)
            return items.indices.contains(next) ? Target(id: items[next].id, start: items[next].start) : nil
        }
        let found = forward
            ? items.first { $0.start > playhead + tolerance }
            : items.last { $0.start < playhead - tolerance }
        return found.map { Target(id: $0.id, start: $0.start) }
    }

    /// The lane drawn above (`down` false) or below `track`, in the order the timeline shows them; nil at the top or bottom.
    public static func lane(down: Bool, from track: Int, in project: Project) -> Int? {
        let order = LaneLayout(project, top: 0).lanes.map(\.track)
        guard let index = order.firstIndex(of: track) else {
            return order.first
        }
        let next = index + (down ? 1 : -1)
        return order.indices.contains(next) ? order[next] : nil
    }

    /// The clip on `track` under the playhead, if any.
    public static func item(onTrack track: Int, at playhead: Double, in project: Project) -> Target? {
        items(onTrack: track, in: project).first { playhead >= $0.start - tolerance && playhead < $0.end }.map { Target(id: $0.id, start: $0.start) }
    }

    /// The range after I (`isStart`) or O at `time`, keeping the other end of `current`. Marking a start at or after the end,
    /// or an end at or before the start, drops the other end back to the edge of the timeline. Nil when the two ends meet.
    public static func marking(_ isStart: Bool, at time: Double, current: Range<Double>?, duration: Double) -> Range<Double>? {
        let time = TimelineSelection.clamped(time, to: duration)
        let lower: Double
        let upper: Double
        if isStart {
            lower = time
            upper = current.map(\.upperBound).flatMap { $0 > time ? $0 : nil } ?? duration
        } else {
            upper = time
            lower = current.map(\.lowerBound).flatMap { $0 < time ? $0 : nil } ?? 0
        }
        return lower < upper ? lower..<upper : nil
    }
}
