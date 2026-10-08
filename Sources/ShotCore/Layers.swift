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
}

extension Annotation {
    /// What the layers panel calls it: the first words of a text or note, else its kind.
    /// A blur, pixelate or spotlight says "(image)", since it only ever acts on the image.
    public var layerName: String {
        switch kind {
        case .arrow: "Arrow"
        case .line: "Line"
        case let .shape(shape, _): shape.title
        case .highlight: "Highlight"
        case .pixelate: "Pixelate (image)"
        case .blur: "Blur (image)"
        case .spotlight: "Spotlight (image)"
        case let .text(string, _, _): Self.firstWords(of: string) ?? "Text"
        case let .note(string, _): Self.firstWords(of: string) ?? "Note"
        case let .counter(number, _): "Step \(number)"
        case .freehand: "Pen"
        case .marker: "Highlighter"
        case .image: "Image"
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

    /// True for the kinds that act on the image under them rather than being drawn over it.
    public var isImageEffect: Bool {
        switch kind {
        case .pixelate, .blur, .spotlight: true
        default: false
        }
    }
}

extension Project {
    /// The overlay tracks, back to front: the layers the panel lists, top row last.
    public var overlayTracks: [Track] {
        tracks.filter { $0.kind == .overlay }
    }

    /// Puts the overlay tracks in the order `reorder` returns, leaving the other tracks where they are.
    private func reorderingOverlays(_ reorder: ([Track]) -> [Track]) -> Project {
        let slots = tracks.indices.filter { tracks[$0].kind == .overlay }
        var result = self
        for (slot, track) in zip(slots, reorder(slots.map { tracks[$0] })) {
            result.tracks[slot] = track
        }
        return result
    }

    public func movingOverlays(_ ids: Set<UUID>, _ move: LayerMove) -> Project {
        reorderingOverlays { $0.moving(ids, move) }
    }

    /// Lifts the overlay tracks in `ids` out and puts them back together at `index` among the other overlay tracks, back to front.
    public func movingOverlays(_ ids: Set<UUID>, toIndex index: Int) -> Project {
        reorderingOverlays { $0.moving(ids, toIndex: index) }
    }

    /// Hides or shows, locks or unlocks, the overlay tracks in `ids`.
    public func setting(_ flag: WritableKeyPath<Track, Bool>, to value: Bool, ofOverlays ids: Set<UUID>) -> Project {
        var result = self
        for index in result.tracks.indices where result.tracks[index].kind == .overlay && ids.contains(result.tracks[index].id) {
            result.tracks[index][keyPath: flag] = value
        }
        return result
    }

    /// Removes every annotation on the overlay tracks in `ids`, and the tracks.
    public func deletingOverlays(_ ids: Set<UUID>) -> Project {
        var result = self
        result.tracks.removeAll { $0.kind == .overlay && ids.contains($0.id) }
        return result
    }
}

extension Track {
    /// What the layers panel calls an overlay track: its first annotation, and how many others share the track.
    public var layerName: String {
        guard let first = annotations.first else {
            return "Empty"
        }
        return annotations.count > 1 ? "\(first.annotation.layerName) +\(annotations.count - 1)" : first.annotation.layerName
    }
}
