import CoreGraphics
import Foundation

/// The outline the image editor flashes after an undo or redo, round each mark it changed, so the person sees what
/// happened even when the change is small or off to one side. It's drawn on the canvas only, never into an export.
public enum UndoFlash {
    /// The part of `Moment.undoFlash` the outline holds at full strength before it fades.
    public static let hold = 0.35

    /// The image-space rects to outline after the marks went from `before` to `after`: one for each mark added,
    /// changed or removed, a removed one at the place it was. A step that changed no mark, such as a crop or a new
    /// background, gives none. Marks that only moved in the stacking order aren't outlined.
    public static func rects(from before: [Annotation], to after: [Annotation]) -> [CGRect] {
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Set(after.map(\.id))
        let changed = after.filter { old[$0.id] != $0 }
        let removed = before.filter { !new.contains($0.id) }
        return (changed + removed).map(outline).filter { !$0.isNull && !$0.isEmpty }
    }

    /// What the outline goes round: the mark with its stroke and anything its style paints past it, as the selection
    /// outline does.
    static func outline(_ annotation: Annotation) -> CGRect {
        annotation.bounds.insetBy(dx: -annotation.lineWidth, dy: -annotation.lineWidth).union(annotation.paintedBounds)
    }

    /// The outline's opacity at `progress`, from 0 to 1: full for `hold`, then easing out to nothing.
    public static func opacity(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        guard t > hold else {
            return 1
        }
        let fade = (t - hold) / (1 - hold)
        return 1 - fade * fade
    }
}
