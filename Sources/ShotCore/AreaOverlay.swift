import CoreGraphics
import Foundation

/// The round handles drawn on an area while it is made (Capture › Area capture). Rects are in the overlay's view space,
/// with y going up, as AppKit draws it.
public enum AreaHandles {
    /// A handle's diameter, before its ink edge.
    public static let diameter: CGFloat = 10
    /// A side shorter than this has no handle at its middle, so the handles don't crowd a small area.
    static let middleMinimum: CGFloat = 48
    /// An area with both sides shorter than this has no handles, since they'd cover it.
    static let cornerMinimum: CGFloat = 12

    /// The centre of each handle: the four corners, then the middle of each side long enough to have one.
    public static func points(around rect: CGRect) -> [CGPoint] {
        if rect.width < cornerMinimum, rect.height < cornerMinimum {
            return []
        }
        var points = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        if rect.width >= middleMinimum {
            points += [CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY)]
        }
        if rect.height >= middleMinimum {
            points += [CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY)]
        }
        return points
    }
}

/// Where the size and ratio chips go: above the area's top-left corner, as the board draws them, else below it, else just
/// inside its top-left corner. They stay on screen and off anything in `avoiding`, such as the capture bar or the loupe.
public enum AreaLabelPlacement {
    /// From the area's edge to the near side of the chips.
    public static let gap: CGFloat = 14
    /// The least room kept between the chips and the screen's edge.
    public static let margin: CGFloat = 8

    /// The frame of chips of `size` for `area`, in `bounds`.
    public static func frame(of size: CGSize, for area: CGRect, in bounds: CGRect, avoiding: [CGRect] = []) -> CGRect {
        let room = bounds.insetBy(dx: margin, dy: margin)
        let x = min(max(area.minX, room.minX), max(room.maxX - size.width, room.minX))
        let candidates = [
            CGRect(x: x, y: area.maxY + gap, width: size.width, height: size.height),
            CGRect(x: x, y: area.minY - gap - size.height, width: size.width, height: size.height),
        ]
        for candidate in candidates where room.contains(candidate) && !avoiding.contains(where: { $0.intersects(candidate) }) {
            return candidate
        }
        // Inside the area, below its top edge, kept on screen when the area runs off the top.
        let top = min(area.maxY, room.maxY) - margin - size.height
        return CGRect(x: min(max(area.minX + margin, room.minX), max(room.maxX - size.width, room.minX)), y: max(top, room.minY), width: size.width, height: size.height)
    }
}

/// The magnifier loupe (Capture › Area capture): a round, zoomed view of the device pixels around the pointer, one pixel per
/// cell of its grid, with the pixel under the pointer in the middle.
public enum Loupe {
    /// Pixels across the loupe. Odd, so one sits in the middle.
    public static let cells = 11
    /// The loupe's diameter at the default text size.
    public static let side: CGFloat = 132
    /// From the pointer to the loupe's near corner, across and down.
    public static let offset: CGFloat = 22
    /// The least room kept between the loupe's ring and the screen's edge.
    static let margin: CGFloat = 8

    /// The device pixel under `point`, counted from the image's top-left corner and kept inside the image.
    public static func pixel(at point: CGPoint, viewHeight: CGFloat, scale: CGFloat, imageSize: CGSize) -> (x: Int, y: Int) {
        let x = Int((point.x * scale).rounded(.down))
        let y = Int(((viewHeight - point.y) * scale).rounded(.down))
        return (min(max(x, 0), max(Int(imageSize.width) - 1, 0)), min(max(y, 0), max(Int(imageSize.height) - 1, 0)))
    }

    /// The square of pixels the loupe shows, centred on `pixel`, in image space with y going down; part of it can lie off the image.
    public static func source(around pixel: (x: Int, y: Int)) -> CGRect {
        let half = cells / 2
        return CGRect(x: pixel.x - half, y: pixel.y - half, width: cells, height: cells)
    }

    /// Where the part of `source` that's on the image lands inside `loupe` (view space, y up), so a pixel near the screen's
    /// edge stays in the middle rather than the crop stretching to fill. Nil when none of it is on the image.
    public static func destination(of source: CGRect, imageSize: CGSize, in loupe: CGRect) -> (crop: CGRect, rect: CGRect)? {
        let visible = source.intersection(CGRect(origin: .zero, size: imageSize))
        guard !visible.isNull, visible.width > 0, visible.height > 0 else {
            return nil
        }
        let cell = loupe.width / CGFloat(cells)
        let rect = CGRect(
            x: loupe.minX + (visible.minX - source.minX) * cell,
            y: loupe.maxY - (visible.maxY - source.minY) * cell,
            width: visible.width * cell,
            height: visible.height * cell
        )
        return (visible, rect)
    }

    /// The loupe's frame for a pointer at `pointer`: `offset` away from it in the direction given, as the board puts it below
    /// and to the right, or the next corner round that is on screen and clear of `avoiding`. `outset` is how far its rings
    /// reach beyond the frame.
    public static func frame(side: CGFloat, outset: CGFloat, at pointer: CGPoint, right: Bool, up: Bool, in bounds: CGRect, avoiding: [CGRect] = []) -> CGRect {
        let room = bounds.insetBy(dx: margin + outset, dy: margin + outset)
        func frame(_ right: Bool, _ up: Bool) -> CGRect {
            CGRect(
                x: right ? pointer.x + offset : pointer.x - offset - side,
                y: up ? pointer.y + offset : pointer.y - offset - side,
                width: side, height: side
            )
        }
        let candidates = [frame(right, up), frame(!right, up), frame(right, !up), frame(!right, !up)]
        let onScreen = candidates.filter { room.contains($0) }
        if let clear = onScreen.first(where: { candidate in !avoiding.contains { $0.intersects(candidate.insetBy(dx: -outset, dy: -outset)) } }) {
            return clear
        }
        if let first = onScreen.first {
            return first
        }
        // A screen too small for any corner: keep the first one as far on screen as it goes.
        var first = candidates[0]
        first.origin.x = min(max(first.minX, room.minX), room.maxX - side)
        first.origin.y = min(max(first.minY, room.minY), room.maxY - side)
        return first
    }
}
