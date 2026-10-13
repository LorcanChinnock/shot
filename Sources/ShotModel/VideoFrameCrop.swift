import Foundation

/// The part of a video's canvas its export shows. The crop is in the canvas's pixels, top-left origin and y down, and
/// the output is that part on whole pixels with even sides, as H.264 wants, so cropping off the menu bar gives a
/// smaller video rather than a scaled-up one.
public enum VideoFrameCrop {
    /// The least a frame crop's width or height can be, as an agent's crop of a video allows.
    public static let minimumSize: CGFloat = 16

    /// What of a `canvas` the export shows: all of it with even sides when there's no `crop`, or the crop kept within
    /// the canvas, its origin on a whole pixel and its sides rounded down to even ones.
    public static func outputRect(crop: CGRect?, canvas: CGSize) -> CGRect {
        let whole = CGRect(origin: .zero, size: CGSize(width: max(2, (canvas.width / 2).rounded() * 2), height: max(2, (canvas.height / 2).rounded() * 2)))
        guard let crop else {
            return whole
        }
        let kept = crop.standardized.intersection(CGRect(origin: .zero, size: canvas))
        guard !kept.isNull else {
            return whole
        }
        let x = kept.minX.rounded(), y = kept.minY.rounded()
        let width = max(2, evenFloor(min(kept.maxX, canvas.width) - x))
        let height = max(2, evenFloor(min(kept.maxY, canvas.height) - y))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// `crop` as a frame crop: `nil` when it shows the whole canvas or too little of it to keep.
    public static func normalized(_ crop: CGRect?, canvas: CGSize) -> CGRect? {
        guard let crop else {
            return nil
        }
        let kept = crop.standardized.intersection(CGRect(origin: .zero, size: canvas))
        guard !kept.isNull, kept.width >= minimumSize, kept.height >= minimumSize else {
            return nil
        }
        let whole = outputRect(crop: nil, canvas: canvas)
        let output = outputRect(crop: kept, canvas: canvas)
        return output == whole ? nil : output
    }

    private static func evenFloor(_ value: CGFloat) -> CGFloat {
        let whole = value.rounded(.down)
        return whole - whole.truncatingRemainder(dividingBy: 2)
    }
}

extension ImageCrop {
    /// What's left of a picture of `size`, in its pixels with a top-left origin.
    public func keptRect(in size: CGSize) -> CGRect {
        let left = min(max(left, 0), 1), top = min(max(top, 0), 1)
        let width = max(size.width * (1 - left - min(max(right, 0), 1)), 1)
        let height = max(size.height * (1 - top - min(max(bottom, 0), 1)), 1)
        return CGRect(x: size.width * left, y: size.height * top, width: width, height: height)
    }
}
