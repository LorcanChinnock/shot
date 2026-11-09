import CoreGraphics
import Foundation

/// The crop bar, from Edit › Image editor · crop and combine: the floating bar at the foot of the canvas in crop mode, with
/// the aspect, the crop's size, Reset, Cancel and Crop.
public enum CropBar {
    /// The size, in pixels, that applying `draft` keeps. The frame's crop is taken on whole pixels within `contentRect`,
    /// as `EditorDocument.crop(to:)` does; a placed image's crop keeps the draft as it is.
    public static func keptSize(draft: CGRect, croppingImage: Bool, contentRect: CGRect) -> CGSize {
        if croppingImage {
            return draft.size
        }
        let kept = draft.integral.intersection(contentRect)
        return kept.isNull ? .zero : kept.size
    }

    /// The bar's top-left corner on a canvas of `canvas` points, with y running down. It sits centred at the foot, as on
    /// the board, the canvas foot's inset from the bottom. `foot` is the size of the zoom control and Canvas menu at the
    /// bottom left; when a centred bar would reach them it moves right, and when that's still too narrow it sits centred
    /// above them.
    public static func origin(bar: CGSize, in canvas: CGSize, foot: CGSize, inset: CGFloat = 16) -> CGPoint {
        let bottom = canvas.height - inset - bar.height
        let clear = inset + foot.width + gap
        let centred = ((canvas.width - bar.width) / 2).rounded()
        if centred >= clear {
            return CGPoint(x: centred, y: bottom)
        }
        let right = canvas.width - inset - bar.width
        if right >= clear {
            return CGPoint(x: right, y: bottom)
        }
        return CGPoint(x: max(inset, centred), y: canvas.height - inset - foot.height - gap - bar.height)
    }

    /// The space the bar keeps from the zoom control and Canvas menu.
    public static let gap: CGFloat = 8

    /// How much of the canvas's bottom the bar at `origin` covers, which the fitted image keeps clear of, so the crop's
    /// bottom handles are never under it.
    public static func clearance(origin: CGPoint, in canvas: CGSize) -> CGFloat {
        max(0, canvas.height - origin.y)
    }
}
