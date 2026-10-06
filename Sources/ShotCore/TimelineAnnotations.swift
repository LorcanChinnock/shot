import CoreGraphics
import Foundation

extension Project {
    public func annotationClip(_ id: UUID) -> AnnotationClip? {
        tracks.lazy.flatMap(\.annotations).first { $0.id == id }
    }

    /// Every annotation clip, bottom track first, which is also the order they're drawn in.
    public var annotationClips: [AnnotationClip] {
        tracks.flatMap(\.annotations)
    }

    /// The clips showing at `time`, in drawing order.
    public func annotationClips(at time: Double) -> [AnnotationClip] {
        annotationClips.filter { $0.start <= time && time < $0.end }
    }

    /// Shows `annotation` from `start` on the first overlay track it fits on, or on a new one above the rest,
    /// for `duration` seconds or until the project ends, whichever comes first, but never under `TrimRange.minimumLength`.
    public func adding(annotation: Annotation, at start: Double, duration: Double = AnnotationClip.defaultDuration) -> (project: Project, clip: UUID) {
        let start = max(0, start)
        let room = self.duration - start
        // With nothing of the project left to show it over, it runs its full length past the end.
        let length = room > 0 ? max(TrimRange.minimumLength, min(duration, room)) : duration
        let clip = AnnotationClip(annotation: annotation, start: start, duration: length)
        var result = self
        let lane = result.tracks.indices.first { index in
            result.tracks[index].kind == .overlay && !result.tracks[index].isLocked
                && result.tracks[index].annotations.allSatisfy { $0.end <= clip.start + 1e-9 || $0.start >= clip.end - 1e-9 }
        }
        if let lane {
            result.tracks[lane].annotations.append(clip)
            result.tracks[lane].annotations.sort { $0.start < $1.start }
        } else {
            result.tracks.append(Track(kind: .overlay, annotations: [clip]))
        }
        return (result, clip.id)
    }

    /// Replaces what an annotation clip shows, keeping its place on the timeline.
    public func setting(annotation: Annotation, ofClip id: UUID) -> Project? {
        guard annotationClip(id) != nil else {
            return nil
        }
        return changingAnnotations([id]) { $0.annotation = annotation }
    }

    /// The next counter number: one more than the highest on the timeline.
    public var nextCounterNumber: Int {
        annotationClips.map(\.annotation).nextCounterNumber
    }

    // MARK: Used by moving, trimming and deleting a clip

    func deletingAnnotation(_ id: UUID) -> Project? {
        var result = self
        for index in result.tracks.indices {
            result.tracks[index].annotations.removeAll { $0.id == id }
        }
        result.tracks = result.tracks.enumerated().filter { $0.offset == 0 || !$0.element.isEmpty }.map(\.element)
        return result
    }

    func movingAnnotation(_ id: UUID, toStart start: Double, snapWithin threshold: Double?, snapTo extra: [Double]) -> Project? {
        guard let clip = annotationClip(id), let track = tracks.firstIndex(where: { $0.annotations.contains { $0.id == id } }) else {
            return nil
        }
        var target = max(0, start)
        if let threshold {
            let points = snapPoints(excluding: [id]) + extra
            let toStart = Snapping.snap(target, to: points, within: threshold).map { $0 - target }
            let toEnd = Snapping.snap(target + clip.duration, to: points, within: threshold).map { $0 - (target + clip.duration) }
            if let nudge = [toStart, toEnd].compactMap(\.self).min(by: { abs($0) < abs($1) }) {
                target += nudge
            }
        }
        let others = tracks[track].annotations.filter { $0.id != id }
        let before = others.filter { $0.end <= clip.start + 1e-9 }.map(\.end).max() ?? 0
        let after = others.filter { $0.start >= clip.end - 1e-9 }.map(\.start).min() ?? .infinity
        let clamped = min(max(target, before), after - clip.duration)
        return changingAnnotations([id]) { $0.start = max(0, clamped) }
    }

    func trimmingAnnotation(_ id: UUID, _ edge: TrimHandle, toTimeline time: Double, snapWithin threshold: Double?, snapTo extra: [Double]) -> Project? {
        guard let clip = annotationClip(id), let track = tracks.firstIndex(where: { $0.annotations.contains { $0.id == id } }) else {
            return nil
        }
        var target = time
        if let threshold {
            target = Snapping.snap(target, to: snapPoints(excluding: [id]) + extra, within: threshold) ?? target
        }
        let others = tracks[track].annotations.filter { $0.id != id }
        let before = others.filter { $0.end <= clip.start + 1e-9 }.map(\.end).max() ?? 0
        let after = others.filter { $0.start >= clip.end - 1e-9 }.map(\.start).min() ?? .infinity
        switch edge {
        case .start:
            let start = min(max(target, before), clip.end - TrimRange.minimumLength)
            return changingAnnotations([id]) {
                $0.duration = clip.end - start
                $0.start = start
                $0.animation = $0.animation.shifted(by: clip.start - start)
            }
        case .end:
            let end = min(max(target, clip.start + TrimRange.minimumLength), after)
            return changingAnnotations([id]) { $0.duration = end - clip.start }
        }
    }

    func changingAnnotations(_ ids: [UUID], _ change: (inout AnnotationClip) -> Void) -> Project {
        var result = self
        for track in result.tracks.indices {
            for index in result.tracks[track].annotations.indices where ids.contains(result.tracks[track].annotations[index].id) {
                change(&result.tracks[track].annotations[index])
            }
        }
        return result
    }
}

extension Track {
    var isEmpty: Bool { clips.isEmpty && annotations.isEmpty }
}
