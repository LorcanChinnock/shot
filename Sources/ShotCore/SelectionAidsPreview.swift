import CoreGraphics
import Foundation

/// Where things go in Settings › Capture's preview of picking an area: the area, dragged from a fixed corner to the
/// pointer, and the loupe beside the pointer. Points are the preview's own, with y going down, as SwiftUI lays it out.
public struct SelectionAidsPreviewLayout: Equatable, Sendable {
    /// The corner the drag starts from, where the board draws the area's top left.
    public static let anchor = CGPoint(x: 40, y: 30)
    /// Where the pointer rests while it isn't over the preview, giving the board's 170 × 80 pt area.
    public static let restingPointer = CGPoint(x: 210, y: 110)
    /// The smallest the area gets, so it never collapses to a line.
    public static let minimumSide: CGFloat = 24
    /// The least room kept between the pointer, or the loupe, and the preview's edge.
    public static let margin: CGFloat = 6
    /// How much the loupe magnifies the preview, and how many of its points it shows across, odd so one sits in the middle.
    public static let magnification: CGFloat = 6
    public static let cells = 11
    /// From the pointer to the loupe's near side, across and down.
    public static let loupeGap: CGFloat = 12
    /// The preview pictures a Retina screen, so each point is two pixels.
    public static let pixelScale: CGFloat = 2

    public static var loupeSide: CGFloat { magnification * CGFloat(cells) }

    /// The pointer, kept far enough right of and below the anchor for the smallest area, and inside the preview.
    public let pointer: CGPoint
    public let size: CGSize

    /// `pointer` is where the mouse is over the preview, or nil to rest.
    public init(size: CGSize, pointer: CGPoint?) {
        let wanted = pointer ?? Self.restingPointer
        let minX = Self.anchor.x + Self.minimumSide
        let minY = Self.anchor.y + Self.minimumSide
        self.size = size
        self.pointer = CGPoint(
            x: min(max(wanted.x, minX), max(size.width - Self.margin, minX)),
            y: min(max(wanted.y, minY), max(size.height - Self.margin, minY))
        )
    }

    /// The area from the anchor to the pointer.
    public var area: CGRect {
        CGRect(x: Self.anchor.x, y: Self.anchor.y, width: pointer.x - Self.anchor.x, height: pointer.y - Self.anchor.y)
    }

    /// The area's size in pixels, as the size label gives it.
    public var pixelSize: (width: Int, height: Int) {
        (Int((area.width * Self.pixelScale).rounded()), Int((area.height * Self.pixelScale).rounded()))
    }

    /// The pixel under the pointer, counted from the preview's top left, as the loupe's readout gives it.
    public var pixel: (x: Int, y: Int) {
        (Int((pointer.x * Self.pixelScale).rounded(.down)), Int((pointer.y * Self.pixelScale).rounded(.down)))
    }

    /// The loupe: below and right of the pointer, as on the overlay, flipped to the other side where it wouldn't fit.
    public var loupe: CGRect {
        let side = Self.loupeSide
        let right = pointer.x + Self.loupeGap
        let below = pointer.y + Self.loupeGap
        let x = right + side + Self.margin <= size.width ? right : pointer.x - Self.loupeGap - side
        let y = below + side + Self.margin <= size.height ? below : pointer.y - Self.loupeGap - side
        return CGRect(x: x, y: max(y, Self.margin), width: side, height: side)
    }

    /// The preview point the loupe's middle cell shows: the middle of the point under the pointer.
    public var loupeCentre: CGPoint {
        CGPoint(x: pointer.x.rounded(.down) + 0.5, y: pointer.y.rounded(.down) + 0.5)
    }
}
