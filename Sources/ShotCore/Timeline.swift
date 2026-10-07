import CoreGraphics
import Foundation

/// How a video clip sits on the canvas. At rest it's scaled to fit the canvas and centred.
public struct ClipTransform: Equatable, Hashable, Codable, Sendable {
    /// How far the clip's centre is from the canvas centre, in canvas pixels, y down.
    public var offset: CGSize
    /// 1 is scaled to fit the canvas.
    public var scale: Double
    /// Clockwise, in radians.
    public var rotation: Double
    public var opacity: Double

    public static let identity = ClipTransform()

    public init(offset: CGSize = .zero, scale: Double = 1, rotation: Double = 0, opacity: Double = 1) {
        self.offset = offset
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
    }
}

/// A stretch of one source file placed on a track, in seconds.
public struct Clip: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var source: URL
    /// Length of the whole source, so a trimmed edge can be dragged back out to it.
    public var sourceDuration: Double
    public var sourceStart: Double
    public var sourceEnd: Double
    /// Where the clip begins on the timeline.
    public var start: Double
    /// The clip that moves with this one, such as a video's own audio.
    public var linkedID: UUID?
    /// The picture's size as it plays, after any rotation the file asks for; zero for sound alone.
    public var size: CGSize
    public var transform: ClipTransform
    /// 1 plays the sound as recorded.
    public var volume: Double
    /// Keyframes for the properties above, in seconds from `start`.
    public var animation: ClipAnimation

    public init(id: UUID = UUID(), source: URL, sourceDuration: Double, sourceStart: Double = 0, sourceEnd: Double? = nil, start: Double = 0, linkedID: UUID? = nil, size: CGSize = .zero, transform: ClipTransform = .identity, volume: Double = 1, animation: ClipAnimation = ClipAnimation()) {
        self.id = id
        self.source = source
        self.sourceDuration = sourceDuration
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd ?? sourceDuration
        self.start = start
        self.linkedID = linkedID
        self.size = size
        self.transform = transform
        self.volume = volume
        self.animation = animation
    }

    /// The plain values of its animatable properties.
    public var propertyValues: PropertyValues {
        PropertyValues(position: transform.offset, scale: transform.scale, rotation: transform.rotation, opacity: transform.opacity, volume: volume)
    }

    /// Its properties at timeline `time`, with the keyframes applied.
    public func values(atTimeline time: Double) -> PropertyValues {
        animation.values(at: time - start, base: propertyValues)
    }

    /// Its transform at timeline `time`.
    public func transform(atTimeline time: Double) -> ClipTransform {
        let values = values(atTimeline: time)
        return ClipTransform(offset: values.position, scale: values.scale, rotation: values.rotation, opacity: values.opacity)
    }

    public var length: Double { sourceEnd - sourceStart }
    public var end: Double { start + length }
}

/// An annotation shown over the video from `start` for `duration` seconds.
public struct AnnotationClip: Equatable, Codable, Sendable, Identifiable {
    /// How long a new annotation shows, unless the project ends sooner.
    public static let defaultDuration: Double = 3

    public var id: UUID
    public var annotation: Annotation
    public var start: Double
    public var duration: Double
    /// Moves, scales, turns and fades the whole annotation, on top of where it was drawn.
    public var transform: ClipTransform
    /// How much of an arrow or pen stroke is drawn, 1 being all of it.
    public var reveal: Double
    public var animation: ClipAnimation

    public init(id: UUID = UUID(), annotation: Annotation, start: Double, duration: Double, transform: ClipTransform = .identity, reveal: Double = 1, animation: ClipAnimation = ClipAnimation()) {
        self.id = id
        self.annotation = annotation
        self.start = start
        self.duration = duration
        self.transform = transform
        self.reveal = reveal
        self.animation = animation
    }

    public var end: Double { start + duration }

    public var propertyValues: PropertyValues {
        PropertyValues(position: transform.offset, scale: transform.scale, rotation: transform.rotation, opacity: transform.opacity, reveal: reveal)
    }

    public func values(atTimeline time: Double) -> PropertyValues {
        animation.values(at: time - start, base: propertyValues)
    }
}

public struct Track: Equatable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case video, audio, overlay
    }

    public var id: UUID
    public var kind: Kind
    /// In timeline order.
    public var clips: [Clip]
    /// What an `.overlay` track holds, in timeline order.
    public var annotations: [AnnotationClip]
    public var isLocked: Bool
    public var isHidden: Bool
    public var isMuted: Bool

    public init(id: UUID = UUID(), kind: Kind, clips: [Clip] = [], annotations: [AnnotationClip] = [], isLocked: Bool = false, isHidden: Bool = false, isMuted: Bool = false) {
        self.id = id
        self.kind = kind
        self.clips = clips
        self.annotations = annotations
        self.isLocked = isLocked
        self.isHidden = isHidden
        self.isMuted = isMuted
    }
}

/// What the video editor edits: tracks of clips on one timeline, so its length is where the last clip ends.
/// The first track is the main one, which closes gaps as clips are cut or trimmed; the clips linked to it follow.
public struct Project: Equatable, Codable, Sendable {
    /// Edits closer together than this don't make a clip, since a 600 timescale can't hold it.
    static let shortestClip = CutList.shortestSection

    public var canvasSize: CGSize
    public var tracks: [Track]

    /// A recording as one clip on the main track, with its sound as a linked clip on an audio track.
    public init(source: URL, duration: Double, canvasSize: CGSize, hasAudio: Bool) {
        self.canvasSize = canvasSize
        var video = Clip(source: source, sourceDuration: duration, size: canvasSize)
        var tracks = [Track(kind: .video, clips: [video])]
        if hasAudio {
            let audio = Clip(source: source, sourceDuration: duration, linkedID: video.id)
            video.linkedID = audio.id
            tracks[0].clips = [video]
            tracks.append(Track(kind: .audio, clips: [audio]))
        }
        self.tracks = tracks
    }

    public var main: Track { tracks[0] }

    public var duration: Double {
        max(tracks.lazy.flatMap(\.clips).map(\.end).max() ?? 0, tracks.lazy.flatMap(\.annotations).map(\.end).max() ?? 0)
    }

    // MARK: Editing

    /// Splits every clip on an unlocked track that spans `time`; nil when none does.
    public func splitting(at time: Double) -> Project? {
        var split = self
        let trackIndices = tracks.indices.filter { !tracks[$0].isLocked }
        return split.split(at: time, tracks: trackIndices) ? split : nil
    }

    /// Cuts out `range` of the timeline, closing the gap on the main track and in the clips linked to it.
    /// Nil when that would leave less than `TrimRange.minimumLength`.
    public func deleting(range: Range<Double>) -> Project? {
        guard range.lowerBound < range.upperBound else {
            return self
        }
        var result = self
        let followers = Set(main.clips.compactMap(\.linkedID))
        let affected = result.tracks.indices.filter { $0 == 0 || result.tracks[$0].clips.contains { followers.contains($0.id) } }
        result.split(at: range.lowerBound, tracks: affected)
        result.split(at: range.upperBound, tracks: affected)
        let touched = Set(result.main.clips.flatMap { [$0.id] + [$0.linkedID].compactMap(\.self) })
        for index in affected {
            result.tracks[index].clips.removeAll { touched.contains($0.id) && $0.start >= range.lowerBound - Self.shortestClip && $0.end <= range.upperBound + Self.shortestClip }
        }
        result.reflowMain()
        return result.duration >= TrimRange.minimumLength - 1e-9 ? result : nil
    }

    /// Cuts a main-track clip out and closes the gap, or removes any other clip with the clip linked to it.
    /// Nil for a recording's own sound, and when that would leave the main track with too little.
    public func deleting(clip id: UUID) -> Project? {
        if annotationClip(id) != nil {
            return deletingAnnotation(id)
        }
        if let clip = main.clips.first(where: { $0.id == id }) {
            return deleting(range: clip.start..<clip.end)
        }
        let followers = Set(main.clips.compactMap(\.linkedID))
        guard let clip = tracks.lazy.flatMap(\.clips).first(where: { $0.id == id }), !followers.contains(id) else {
            return nil
        }
        var result = self
        let removed = Set([id, clip.linkedID].compactMap(\.self))
        for index in result.tracks.indices {
            result.tracks[index].clips.removeAll { removed.contains($0.id) }
        }
        result.tracks = result.tracks.enumerated().filter { $0.offset == 0 || !$0.element.isEmpty }.map(\.element)
        return result
    }

    /// The main-track clip playing at `time`, or the last one at the very end.
    public func mainClip(at time: Double) -> Clip? {
        main.clips.first { time >= $0.start && time < $0.end } ?? main.clips.last { abs(time - $0.end) <= Self.shortestClip }
    }

    /// Where the timeline starts and ends its clips, for snapping.
    public func snapPoints(excluding ids: Set<UUID> = []) -> [Double] {
        let clips = tracks.flatMap(\.clips).filter { !ids.contains($0.id) }.flatMap { [$0.start, $0.end] }
        let annotations = tracks.flatMap(\.annotations).filter { !ids.contains($0.id) }.flatMap { [$0.start, $0.end] }
        return Array(Set(clips + annotations + [0])).sorted()
    }

    // MARK: Trim and cut, in the recording's own time

    /// The main track's clips as the trim handles and cuts the editor shows, when that's all there is:
    /// one recording on the main track, in order, with its own sound linked and cut the same, and nothing hidden or muted.
    public var trimEdit: TrimEdit? {
        guard let first = main.clips.first, main.clips.allSatisfy({ $0.source == first.source && $0.transform == .identity && $0.animation.isEmpty }),
              tracks.allSatisfy({ !$0.isHidden && !$0.isMuted }) else {
            return nil
        }
        var cuts = CutList()
        for (previous, next) in zip(main.clips, main.clips.dropFirst()) {
            guard next.sourceStart >= previous.sourceEnd else {
                return nil
            }
            cuts = cuts.adding(previous.sourceEnd..<next.sourceStart)
        }
        let followers = tracks.dropFirst().flatMap(\.clips)
        let partners = main.clips.compactMap(\.linkedID)
        guard tracks.count <= 2, partners.isEmpty || partners.count == main.clips.count, followers.map(\.id) == partners else {
            return nil
        }
        for (clip, follower) in zip(main.clips, followers) {
            guard follower.volume == 1, follower.animation.isEmpty, follower.source == clip.source, [follower.sourceStart - clip.sourceStart, follower.sourceEnd - clip.sourceEnd, follower.start - clip.start].allSatisfy({ abs($0) < Self.shortestClip }) else {
                return nil
            }
        }
        let range = TrimRange(start: first.sourceStart, end: main.clips.last!.sourceEnd, duration: first.sourceDuration)
        return TrimEdit(source: first.source, range: range, cuts: cuts)
    }

    /// Drags a trim handle to `time` in the recording; nil when the cuts would leave too little to play.
    public func trimmingMain(_ handle: TrimHandle, toSource time: Double) -> Project? {
        guard let first = main.clips.first, let last = main.clips.last else {
            return self
        }
        var result = self
        switch handle {
        case .start:
            // With clips from several files the handle can only go as far as the first clip.
            let target = min(max(time, 0), isOneRecording ? last.sourceEnd - TrimRange.minimumLength : first.sourceEnd)
            if target >= first.sourceStart {
                return deleting(range: 0..<(isOneRecording ? timelinePosition(ofSource: target) : first.start + target - first.sourceStart))
            }
            let grown = first.sourceStart - target
            result.tracks[0].clips[0].sourceStart = target
            result.tracks[0].clips[0].animation = first.animation.shifted(by: grown)
            result.followingMain { $0.sourceStart = target }
        case .end:
            let target = max(min(time, last.sourceDuration), isOneRecording ? first.sourceStart + TrimRange.minimumLength : last.sourceStart)
            if target <= last.sourceEnd {
                return deleting(range: (isOneRecording ? timelinePosition(ofSource: target) : last.start + target - last.sourceStart)..<duration)
            }
            result.tracks[0].clips[main.clips.count - 1].sourceEnd = target
            result.followingMain(of: last.id) { $0.sourceEnd = target }
        }
        result.reflowMain()
        return result
    }

    /// Cuts the part of `selection`, in the recording, that's still on the timeline; nil when that would leave too little.
    public func cutting(source selection: Range<Double>) -> Project? {
        deleting(range: timelinePosition(ofSource: selection.lowerBound)..<timelinePosition(ofSource: selection.upperBound))
    }

    private var isOneRecording: Bool {
        main.clips.dropFirst().allSatisfy { $0.source == main.clips[0].source }
    }

    /// Where the main track plays source time `time`, or where it next resumes if that part was cut.
    public func timelinePosition(ofSource time: Double) -> Double {
        for clip in main.clips where clip.sourceEnd > time {
            return clip.start + max(0, time - clip.sourceStart)
        }
        return main.clips.last?.end ?? 0
    }

    /// The recording time the main track plays at timeline `time`; at or past the end, where the last clip stops.
    public func sourceTime(atTimeline time: Double) -> Double {
        guard let clip = mainClip(at: time) else {
            return time > 0 ? main.clips.last?.sourceEnd ?? 0 : main.clips.first?.sourceStart ?? 0
        }
        return min(clip.sourceEnd, clip.sourceStart + max(0, time - clip.start))
    }

    // MARK: Private

    @discardableResult
    private mutating func split(at time: Double, tracks indices: [Int]) -> Bool {
        var rightHalves: [UUID: UUID] = [:]
        for track in indices {
            var annotations: [AnnotationClip] = []
            for clip in tracks[track].annotations {
                guard clip.start + Self.shortestClip < time, time < clip.end - Self.shortestClip else {
                    annotations.append(clip)
                    continue
                }
                var left = clip, right = clip
                right.id = UUID()
                left.duration = time - clip.start
                right.start = time
                right.duration = clip.end - time
                (left.animation, right.animation) = clip.animation.splitting(at: time - clip.start)
                rightHalves[clip.id] = right.id
                annotations += [left, right]
            }
            tracks[track].annotations = annotations
            var clips: [Clip] = []
            for clip in tracks[track].clips {
                guard clip.start + Self.shortestClip < time, time < clip.end - Self.shortestClip else {
                    clips.append(clip)
                    continue
                }
                var left = clip, right = clip
                right.id = UUID()
                rightHalves[clip.id] = right.id
                left.sourceEnd = clip.sourceStart + (time - clip.start)
                right.sourceStart = left.sourceEnd
                right.start = time
                (left.animation, right.animation) = clip.animation.splitting(at: time - clip.start)
                clips += [left, right]
            }
            tracks[track].clips = clips
        }
        // A right half moves with the right half of its partner, if that was split too.
        let rightIDs = Set(rightHalves.values)
        for track in indices {
            for index in tracks[track].clips.indices where rightIDs.contains(tracks[track].clips[index].id) {
                tracks[track].clips[index].linkedID = tracks[track].clips[index].linkedID.flatMap { rightHalves[$0] }
            }
        }
        return !rightHalves.isEmpty
    }

    /// Closes the gaps on the main track, moving the clips linked to its clips by the same amounts.
    private mutating func reflowMain() {
        var cursor = 0.0
        var shifts: [UUID: Double] = [:]
        for index in tracks[0].clips.indices {
            let clip = tracks[0].clips[index]
            if let linked = clip.linkedID {
                shifts[linked] = cursor - clip.start
            }
            tracks[0].clips[index].start = cursor
            cursor += clip.length
        }
        for track in tracks.indices.dropFirst() {
            for index in tracks[track].clips.indices {
                if let shift = shifts[tracks[track].clips[index].id] {
                    tracks[track].clips[index].start += shift
                }
            }
        }
    }

    /// Applies `change` to the first main clip's partner.
    private mutating func followingMain(_ change: (inout Clip) -> Void) {
        followingMain(of: main.clips[0].id, change)
    }

    private mutating func followingMain(of id: UUID, _ change: (inout Clip) -> Void) {
        guard let linked = main.clips.first(where: { $0.id == id })?.linkedID else {
            return
        }
        for track in tracks.indices.dropFirst() {
            if let index = tracks[track].clips.firstIndex(where: { $0.id == linked }) {
                change(&tracks[track].clips[index])
            }
        }
    }
}

/// The trim handles and cuts a one-recording project reduces to, which `VideoTrimmer` and `GIFExporter` can write directly.
public struct TrimEdit: Equatable, Sendable {
    public let source: URL
    public let range: TrimRange
    public let cuts: CutList
}
