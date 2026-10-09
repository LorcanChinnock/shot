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
