import CoreGraphics
import Foundation

/// A file to put on the timeline, as AVFoundation reads it.
public struct ImportedMedia: Equatable, Sendable {
    public var source: URL
    public var duration: Double
    /// The picture's size as it plays; nil for sound alone.
    public var size: CGSize?
    public var hasAudio: Bool

    public init(source: URL, duration: Double, size: CGSize?, hasAudio: Bool) {
        self.source = source
        self.duration = duration
        self.size = size
        self.hasAudio = hasAudio
    }
}

extension Project {
    /// Puts `media` on new tracks starting at `start`: its picture on a track above the rest, and its sound on one of its own.
    /// Returns the picture's clip, or the sound's when there's no picture, so it can be selected.
    public func importing(_ media: ImportedMedia, at start: Double) -> (project: Project, clip: UUID)? {
        guard media.duration >= Self.shortestClip else {
            return nil
        }
        var result = self
        let start = max(0, start)
        var picture = media.size.map { Clip(source: media.source, sourceDuration: media.duration, start: start, size: $0) }
        var sound = media.hasAudio ? Clip(source: media.source, sourceDuration: media.duration, start: start) : nil
        picture?.linkedID = sound?.id
        sound?.linkedID = picture?.id
        if let picture {
            result.tracks.append(Track(kind: .video, clips: [picture]))
        }
        if let sound {
            result.tracks.append(Track(kind: .audio, clips: [sound]))
        }
        guard let first = picture?.id ?? sound?.id else {
            return nil
        }
        return (result, first)
    }

    /// Adds `media` to the end of the main track, with its sound after the recording's own.
    public func appending(_ media: ImportedMedia) -> (project: Project, clip: UUID)? {
        guard let size = media.size, media.duration >= Self.shortestClip else {
            return nil
        }
        var result = self
        let start = main.clips.last?.end ?? 0
        var picture = Clip(source: media.source, sourceDuration: media.duration, start: start, size: size)
        if media.hasAudio {
            var sound = Clip(source: media.source, sourceDuration: media.duration, start: start, linkedID: picture.id)
            picture.linkedID = sound.id
            if let audio = result.tracks.firstIndex(where: { $0.kind == .audio && $0.clips.contains { clip in main.clips.contains { $0.linkedID == clip.id } } }) {
                result.tracks[audio].clips.append(sound)
            } else {
                sound.start = start
                result.tracks.append(Track(kind: .audio, clips: [sound]))
            }
        }
        result.tracks[0].clips.append(picture)
        return (result, picture.id)
    }

    /// Moves a clip, and the clip linked to it, so it starts at `start`, never before 0 and never over a neighbour.
    /// With `snapWithin`, its start or end jumps to the nearest clip edge, or of `snapTo`, inside that many seconds.
    /// The main track's clips and their sound stay put. Nil when it can't move.
    public func moving(clip id: UUID, toStart start: Double, snapWithin threshold: Double? = nil, snapTo extra: [Double] = []) -> Project? {
        if annotationClip(id) != nil {
            return movingAnnotation(id, toStart: start, snapWithin: threshold, snapTo: extra)
        }
        guard let clip = clip(id), isFree(clip), let delta = moveDelta(of: clip, toStart: start, snapWithin: threshold, snapTo: extra, keepingIn: group(of: clip)) else {
            return nil
        }
        return changing(group(of: clip).map(\.id)) { $0.start += delta }
    }

    /// Drags an edge of a clip that isn't on the main track to timeline time `time`, with the clip linked to it,
    /// within the source and the neighbours, leaving at least `TrimRange.minimumLength`.
    /// With `snapWithin`, the edge jumps to a clip edge, or of `snapTo`, inside that many seconds.
    public func trimming(clip id: UUID, _ edge: TrimHandle, toTimeline time: Double, snapWithin threshold: Double? = nil, snapTo extra: [Double] = []) -> Project? {
        if annotationClip(id) != nil {
            return trimmingAnnotation(id, edge, toTimeline: time, snapWithin: threshold, snapTo: extra)
        }
        guard let clip = clip(id), isFree(clip) else {
            return nil
        }
        var target = time
        if let threshold {
            let points = snapPoints(excluding: Set([id, clip.linkedID].compactMap(\.self))) + extra
            target = Snapping.snap(target, to: points, within: threshold) ?? target
        }
        var delta = target - (edge == .start ? clip.start : clip.end)
        for member in group(of: clip) {
            let free = freeRange(around: member)
            switch edge {
            case .start:
                delta = min(max(delta, max(-member.sourceStart, free.lowerBound - member.start)), member.length - TrimRange.minimumLength)
            case .end:
                delta = min(max(delta, TrimRange.minimumLength - member.length), min(member.sourceDuration - member.sourceEnd, free.upperBound - member.end))
            }
        }
        return changing(group(of: clip).map(\.id)) {
            switch edge {
            case .start:
                $0.start += delta
                $0.sourceStart += delta
                $0.animation = $0.animation.shifted(by: -delta)
            case .end:
                $0.sourceEnd += delta
            }
        }
    }

    public func setting(transform: ClipTransform, of id: UUID) -> Project? {
        clip(id) == nil ? nil : changing([id]) { $0.transform = transform }
    }

    public func setting(volume: Double, of id: UUID) -> Project? {
        clip(id) == nil ? nil : changing([id]) { $0.volume = min(max(volume, 0), 2) }
    }

    public func clip(_ id: UUID) -> Clip? {
        tracks.lazy.flatMap(\.clips).first { $0.id == id }
    }

    public func trackIndex(of id: UUID) -> Int? {
        tracks.firstIndex { $0.clips.contains { $0.id == id } }
    }

    // MARK: Used by moving a clip to another lane

    /// How far `clip` moves when it's dragged to start at `start`: never before 0, snapped as `moving(clip:toStart:snapWithin:snapTo:)`
    /// does, and no further than each of `members` has room for on its track. Nil when one of them has no room.
    func moveDelta(of clip: Clip, toStart start: Double, snapWithin threshold: Double?, snapTo extra: [Double], keepingIn members: [Clip]) -> Double? {
        var target = max(0, start)
        if let threshold {
            let points = snapPoints(excluding: Set([clip.id, clip.linkedID].compactMap(\.self))) + extra
            let toStart = Snapping.snap(target, to: points, within: threshold).map { $0 - target }
            let toEnd = Snapping.snap(target + clip.length, to: points, within: threshold).map { $0 - (target + clip.length) }
            if let nudge = [toStart, toEnd].compactMap(\.self).min(by: { abs($0) < abs($1) }) {
                target += nudge
            }
        }
        var delta = max(target - clip.start, -clip.start)
        for member in members {
            let range = freeRange(around: member)
            delta = min(max(delta, range.lowerBound - member.start), range.upperBound - member.length - member.start)
        }
        guard members.allSatisfy({ member in
            let range = freeRange(around: member)
            return range.lowerBound <= member.start + delta + 1e-9 && member.end + delta <= range.upperBound + 1e-9
        }) else {
            return nil
        }
        return delta
    }

    /// Whether a clip can be moved and trimmed on its own: not one on the main track, nor the sound of one.
    func isFree(_ clip: Clip) -> Bool {
        !main.clips.contains { $0.id == clip.id || $0.linkedID == clip.id }
    }

    /// `clip` and the clip linked to it.
    func group(of clip: Clip) -> [Clip] {
        [clip] + [clip.linkedID.flatMap(self.clip)].compactMap(\.self)
    }

    func changing(_ ids: [UUID], _ change: (inout Clip) -> Void) -> Project {
        var result = self
        for track in result.tracks.indices {
            for index in result.tracks[track].clips.indices where ids.contains(result.tracks[track].clips[index].id) {
                change(&result.tracks[track].clips[index])
            }
        }
        return result
    }

    // MARK: Private

    /// The stretch of its track a clip may occupy: from the end of the clip before it to the start of the one after.
    private func freeRange(around clip: Clip) -> ClosedRange<Double> {
        guard let track = trackIndex(of: clip.id) else {
            return 0...Double.infinity
        }
        let others = tracks[track].clips.filter { $0.id != clip.id }
        let before = others.filter { $0.end <= clip.start + 1e-9 }.map(\.end).max() ?? 0
        let after = others.filter { $0.start >= clip.end - 1e-9 }.map(\.start).min() ?? .infinity
        return before...after
    }
}
