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

extension CropBar {
    /// The size, in pixels, that applying a video crop of `draft` keeps: the frame's crop comes out on even pixels, as
    /// `VideoFrameCrop.outputRect` exports it, and a clip's keeps its picture's pixels as they are.
    public static func keptSize(videoDraft draft: CGRect, croppingFrame: Bool, canvas: CGSize) -> CGSize {
        croppingFrame ? VideoFrameCrop.outputRect(crop: draft, canvas: canvas).size : draft.standardized.size
    }
}

/// The crop's marks, from Edit › Image editor · crop and combine, in view points around a crop of `crop`, also in view
/// points: an L-shaped mark on each corner, and a short bar across the middle of each side long enough to hold one. Both
/// editors draw them, the image editor in its canvas and the video editor turned with the clip it crops.
public enum CropMarks {
    /// The corner marks are 4 pt thick and 18 pt along each side, starting 3 pt outside the corner.
    public static let thickness: CGFloat = 4
    public static let length: CGFloat = 18
    public static let outset: CGFloat = 3
    /// The side bars are 26 × 5 pt, rounded at 2.5, 4 pt outside their side and 1 pt in.
    public static let barLength: CGFloat = 26
    public static let barWidth: CGFloat = 5
    public static let barRadius: CGFloat = 2.5
    private static let barOutset: CGFloat = 4

    /// Each corner's L as a closed outline of six points, in the order top left, top right, bottom left, bottom right,
    /// with y running down.
    public static func corners(of crop: CGRect) -> [[CGPoint]] {
        [(crop.minX, crop.minY), (crop.maxX, crop.minY), (crop.minX, crop.maxY), (crop.maxX, crop.maxY)].map { x, y in
            let sx: CGFloat = x == crop.minX ? 1 : -1
            let sy: CGFloat = y == crop.minY ? 1 : -1
            let cx = x - sx * outset, cy = y - sy * outset
            return [
                CGPoint(x: cx, y: cy),
                CGPoint(x: cx + sx * length, y: cy),
                CGPoint(x: cx + sx * length, y: cy + sy * thickness),
                CGPoint(x: cx + sx * thickness, y: cy + sy * thickness),
                CGPoint(x: cx + sx * thickness, y: cy + sy * length),
                CGPoint(x: cx, y: cy + sy * length),
            ]
        }
    }

    /// The side bars: top and bottom while the crop is wide enough to hold one clear of its corners, and left and right
    /// while it's tall enough.
    public static func bars(of crop: CGRect) -> [CGRect] {
        let room = barLength + length * 2
        var bars: [CGRect] = []
        if crop.width > room {
            bars.append(CGRect(x: crop.midX - barLength / 2, y: crop.minY - barOutset, width: barLength, height: barWidth))
            bars.append(CGRect(x: crop.midX - barLength / 2, y: crop.maxY - (barWidth - barOutset), width: barLength, height: barWidth))
        }
        if crop.height > room {
            bars.append(CGRect(x: crop.minX - barOutset, y: crop.midY - barLength / 2, width: barWidth, height: barLength))
            bars.append(CGRect(x: crop.maxX - (barWidth - barOutset), y: crop.midY - barLength / 2, width: barWidth, height: barLength))
        }
        return bars
    }
}
