import CoreGraphics
import Foundation

/// An annotation on the pasteboard, so it can be pasted into any editor window.
public enum AnnotationClipboard {
    /// The pasteboard type the editor writes a copied annotation as.
    public static let pasteboardType = "dev.lorcan.Shot.annotation"

    public static func data(for annotation: Annotation) throws -> Data {
        try JSONEncoder().encode(annotation)
    }

    public static func annotation(from data: Data) throws -> Annotation {
        try JSONDecoder().decode(Annotation.self, from: data)
    }
}

/// An arrow key that nudges the selection.
public enum NudgeDirection: Sendable {
    case left, right, up, down

    /// One image pixel, or ten when `large` (Shift is held). Image pixels have a top-left origin, so up is -y.
    public func offset(large: Bool) -> CGVector {
        let step: CGFloat = large ? 10 : 1
        switch self {
        case .left: return CGVector(dx: -step, dy: 0)
        case .right: return CGVector(dx: step, dy: 0)
        case .up: return CGVector(dx: 0, dy: -step)
        case .down: return CGVector(dx: 0, dy: step)
        }
    }
}

extension EditorDocument {
    /// Adds a copy of `annotation`, `step` pixels down and right of it, and returns the copy's id.
    /// A copy that would land off the canvas is centred on it instead, a spot already holding a copy
    /// steps on again so repeated pastes cascade, and a counter takes the next number.
    /// The canvas grows if the copy reaches past its edge.
    @discardableResult
    public mutating func paste(_ annotation: Annotation, step: CGFloat, margin: CGFloat) -> UUID {
        var copy = Annotation(kind: annotation.kind, color: annotation.color, lineWidth: annotation.lineWidth)
        if case let .counter(_, center) = copy.kind {
            copy.kind = .counter(annotations.nextCounterNumber, center: center)
        }
        let offset = CGVector(dx: step, dy: step)
        copy.offset(by: offset)
        if !copy.bounds.intersects(canvasRect) {
            copy.offset(by: CGVector(dx: canvasRect.midX - copy.bounds.midX, dy: canvasRect.midY - copy.bounds.midY))
        }
        if step > 0 {
            while annotations.contains(where: { $0.bounds == copy.bounds }) {
                copy.offset(by: offset)
            }
        }
        annotations.append(copy)
        grow(toFit: copy, margin: margin)
        return copy.id
    }

    /// Moves the annotation with `id` by `delta`, growing the canvas if it now reaches past the edge.
    public mutating func move(_ id: UUID, by delta: CGVector, margin: CGFloat) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }
        annotations[index].offset(by: delta)
        grow(toFit: annotations[index], margin: margin)
    }
}
