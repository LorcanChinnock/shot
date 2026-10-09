import CoreGraphics
import Foundation

public enum LayerMove: Sendable {
    case forward, backward, toFront, toBack
}

extension Array where Element: Identifiable {
    /// The elements, back to front, with those in `ids` moved one step or all the way. Selected elements keep their order among themselves.
    public func moving(_ ids: Set<Element.ID>, _ move: LayerMove) -> [Element] {
        var result = self
        var selected = result.map { ids.contains($0.id) }
        switch move {
        case .toFront:
            return filter { !ids.contains($0.id) } + filter { ids.contains($0.id) }
        case .toBack:
            return filter { ids.contains($0.id) } + filter { !ids.contains($0.id) }
        case .forward:
            for index in stride(from: result.count - 2, through: 0, by: -1) where selected[index] && !selected[index + 1] {
                result.swapAt(index, index + 1)
                selected.swapAt(index, index + 1)
            }
        case .backward:
            for index in stride(from: 1, to: result.count, by: 1) where selected[index] && !selected[index - 1] {
                result.swapAt(index, index - 1)
                selected.swapAt(index, index - 1)
            }
        }
        return result
    }

    /// The elements with those in `ids` lifted out and put back together at `index` among the rest, back to front.
    public func moving(_ ids: Set<Element.ID>, toIndex index: Int) -> [Element] {
        var rest = filter { !ids.contains($0.id) }
        rest.insert(contentsOf: filter { ids.contains($0.id) }, at: Swift.min(Swift.max(index, 0), rest.count))
        return rest
    }
}

public enum LayerList {
    /// Where a drop in a frontmost-first list of `count` layers puts the dragged rows, as the index `moving(_:toIndex:)`
    /// takes: among the layers that stay, counted back to front. `destination` is the row they were dropped before.
    public static func backToFrontIndex(movingOffsets offsets: IndexSet, toOffset destination: Int, count: Int) -> Int {
        let frontIndex = destination - offsets.filter { $0 < destination }.count
        return count - offsets.count - frontIndex
    }

    /// The `destination` that drops the rows in `moving` into the gap before the `gap`th of the rows that stay, as
    /// `backToFrontIndex` takes it, or `nil` when they'd land where they are.
    public static func destination<ID: Hashable>(of ids: [ID], moving: Set<ID>, gap: Int) -> Int? {
        var rest = ids.filter { !moving.contains($0) }
        let staying = rest
        rest.insert(contentsOf: ids.filter { moving.contains($0) }, at: min(max(gap, 0), rest.count))
        guard rest != ids else {
            return nil
        }
        return gap < staying.count ? ids.firstIndex(of: staying[max(gap, 0)]) : ids.count
    }
}

extension Annotation {
    /// What the layers panel calls it: the first words of a text or note, else its kind.
    public var layerName: String {
        switch kind {
        case .arrow: "Arrow"
        case .line: "Line"
        case let .shape(shape, _): shape.title
        case .highlight: "Highlight"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .spotlight: "Spotlight"
        case let .text(string, _, _): Self.firstWords(of: string) ?? "Text"
        case let .note(string, _): Self.firstWords(of: string) ?? "Note"
        case let .counter(number, _): "Step \(number)"
        case .freehand: "Pen"
        case .marker: "Highlighter"
        case .image: "Image"
        }
    }

    /// The SF Symbol for it in the layers panel and the video editor's tracks.
    public var layerSymbol: String {
        switch kind {
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case let .shape(shape, _): shape.symbol
        case .highlight, .marker: "highlighter"
        case .pixelate: "squareshape.split.3x3"
        case .blur: "drop.halffull"
        case .spotlight: "flashlight.on.fill"
        case .text: "textformat"
        case .counter: "1.circle"
        case .note: "note.text"
        case .freehand: "scribble"
        case .image: "photo"
        }
    }

    /// Where drawing it changes the canvas: what it paints, or for a spotlight, everywhere, since the spotlights share one dim.
    var drawnArea: CGRect {
        if case .spotlight = kind {
            return .infinite
        }
        return paintedBounds
    }

    /// How far past where it draws it reads what's under it, on `base`; `nil` when it only paints over it.
    /// A layer that reads acts on everything drawn under it, so this is all the renderer needs to know to draw it in order.
    func backdropReach(base: CGImage) -> CGFloat? {
        switch kind {
        case .pixelate:
            AnnotationRenderer.redactionSize(self, base: base)
        case .blur:
            AnnotationRenderer.redactionSize(self, base: base) * 4
        case let .spotlight(_, style):
            // A Gaussian blur spreads about three times its radius; a darkening reads only the pixel it darkens.
            style.effect == .blur ? style.blurRadius(forImageLength: AnnotationRenderer.longerSide(of: base)) * 3 : 0
        case .arrow, .line, .shape, .highlight, .text, .counter, .note, .freehand, .marker, .image:
            nil
        }
    }

    private static func firstWords(of string: String, limit: Int = 24) -> String? {
        let words = string.split(whereSeparator: \.isWhitespace)
        guard let first = words.first else {
            return nil
        }
        var name = String(first.prefix(limit))
        for word in words.dropFirst() {
            guard name.count + 1 + word.count <= limit else {
                return name + "…"
            }
            name += " " + word
        }
        return name
    }
}

extension EditorDocument {
    /// Removes the annotations in `ids` that aren't locked, and the padding only they needed. Returns the ids removed.
    @discardableResult
    public mutating func deleteLayers(_ ids: Set<UUID>, margin: CGFloat) -> Set<UUID> {
        let removable = Set(annotations.filter { ids.contains($0.id) && !$0.isLocked }.map(\.id))
        guard !removable.isEmpty else {
            return []
        }
        annotations.removeAll { removable.contains($0.id) }
        shrinkPadding(margin: margin)
        return removable
    }
}

/// Where a clip dragged up or down the lanes lands.
public enum LaneDrop: Equatable, Sendable {
    /// Onto the track at this index of `tracks`, or a new one just above it where that's locked, taken or of another kind.
    case onto(Int)
    /// Onto a new track put at this index of `tracks`.
    case insert(Int)
}

extension Project {
    /// The overlay tracks, back to front.
    public var overlayTracks: [Track] {
        tracks.filter { $0.kind == .overlay }
    }

    /// The tracks above the main one, annotations and pictures, which draw in this order, bottom first.
    public var stackedTrackIndices: [Int] {
        tracks.indices.filter { $0 != 0 && tracks[$0].kind != .audio }
    }

    /// The id of the track clip or annotation clip `id` is on.
    public func trackID(of id: UUID) -> UUID? {
        tracks.first { $0.annotations.contains { $0.id == id } || $0.clips.contains { $0.id == id } }?.id
    }

    /// Moves clip `id`, an annotation or a picture off the main track, to start at `start` on the track `drop` picks, as dragging
    /// it up or down the lanes does, snapping as `moving(clip:toStart:snapWithin:snapTo:)` does. A picture's sound stays on its
    /// own track and moves with it in time. The track it leaves goes if that empties it. Nil when it can't move.
    public func moving(clip id: UUID, toStart start: Double, onto drop: LaneDrop, snapWithin threshold: Double? = nil, snapTo extra: [Double] = []) -> Project? {
        guard let source = tracks.firstIndex(where: { $0.annotations.contains { $0.id == id } || $0.clips.contains { $0.id == id } }),
              source != 0, tracks[source].kind != .audio else {
            return nil
        }
        let stayPut = { moving(clip: id, toStart: start, snapWithin: threshold, snapTo: extra) }
        let placed: Range<Double>
        var shift = 0.0
        if let annotation = annotationClip(id) {
            let start = snappedStart(of: annotation, at: start, within: threshold, to: extra)
            placed = start..<(start + annotation.duration)
        } else {
            guard let clip = clip(id), isFree(clip), let delta = moveDelta(of: clip, toStart: start, snapWithin: threshold, snapTo: extra, keepingIn: group(of: clip).filter { $0.id != id }) else {
                return nil
            }
            shift = delta
            placed = (clip.start + delta)..<(clip.end + delta)
        }
        let kind = tracks[source].kind
        let alone = tracks[source].clips.count + tracks[source].annotations.count == 1
        var result = self
        let target: Int
        switch drop {
        case let .onto(index):
            guard tracks.indices.contains(index), index != 0, tracks[index].kind != .audio else {
                return nil
            }
            if index == source {
                return stayPut()
            }
            let track = tracks[index]
            let free = track.clips.allSatisfy { $0.end <= placed.lowerBound + 1e-9 || $0.start >= placed.upperBound - 1e-9 }
                && track.annotations.allSatisfy { $0.end <= placed.lowerBound + 1e-9 || $0.start >= placed.upperBound - 1e-9 }
            if track.kind == kind, !track.isLocked, free {
                target = index
            } else {
                target = index + 1
                result.tracks.insert(Track(kind: kind), at: target)
            }
        case let .insert(index):
            // A new track right next to one it would leave empty is that track, which keeps its lock and visibility.
            if alone, index == source || index == source + 1 {
                return stayPut()
            }
            target = min(max(index, 1), tracks.count)
            result.tracks.insert(Track(kind: kind), at: target)
        }
        guard let from = result.tracks.firstIndex(where: { $0.id == tracks[source].id }) else {
            return nil
        }
        if var annotation = annotationClip(id) {
            annotation.start = placed.lowerBound
            result.tracks[from].annotations.removeAll { $0.id == id }
            result.tracks[target].annotations.append(annotation)
            result.tracks[target].annotations.sort { $0.start < $1.start }
        } else if let clip = clip(id) {
            result = result.changing(group(of: clip).map(\.id)) { $0.start += shift }
            result.tracks[from].clips.removeAll { $0.id == id }
            var moved = clip
            moved.start += shift
            result.tracks[target].clips.append(moved)
            result.tracks[target].clips.sort { $0.start < $1.start }
        }
        if result.tracks[from].isEmpty {
            result.tracks.remove(at: from)
        }
        return result
    }

    /// Moves clip `id`, an annotation or a picture off the main track, one lane up or down, or to the top or bottom lane, keeping
    /// its time. At the top or bottom it takes a lane of its own unless it's already alone there. Nil when it can't move.
    public func moving(clip id: UUID, _ move: LayerMove) -> Project? {
        guard let source = tracks.firstIndex(where: { $0.annotations.contains { $0.id == id } || $0.clips.contains { $0.id == id } }),
              let start = annotationClip(id)?.start ?? clip(id)?.start else {
            return nil
        }
        let stacked = stackedTrackIndices
        let above = stacked.filter { $0 > source }, below = stacked.filter { $0 < source }
        let moved: Project? = switch move {
        case .forward: moving(clip: id, toStart: start, onto: above.first.map(LaneDrop.onto) ?? .insert(source + 1))
        case .backward: movingDown(id, toStart: start, onto: below.last) ?? moving(clip: id, toStart: start, onto: .insert(source))
        case .toFront: moving(clip: id, toStart: start, onto: above.last.map(LaneDrop.onto) ?? .insert(source + 1))
        case .toBack: movingDown(id, toStart: start, onto: below.first) ?? moving(clip: id, toStart: start, onto: .insert(source))
        }
        guard let moved, moved != self else {
            return nil
        }
        return moved
    }

    /// Moves clip `id` onto the lane of track `index`, or onto a new one just under it where that can't take it.
    private func movingDown(_ id: UUID, toStart start: Double, onto index: Int?) -> Project? {
        guard let index, let onto = moving(clip: id, toStart: start, onto: .onto(index)) else {
            return nil
        }
        return onto.trackID(of: id) == tracks[index].id ? onto : moving(clip: id, toStart: start, onto: .insert(index))
    }

    /// Removes every annotation on the overlay tracks in `ids`, and the tracks.
    public func deletingOverlays(_ ids: Set<UUID>) -> Project {
        var result = self
        result.tracks.removeAll { $0.kind == .overlay && ids.contains($0.id) }
        return result
    }
}
