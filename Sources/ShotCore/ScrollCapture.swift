import CoreGraphics
import Foundation

/// What a scrolling capture is doing, for the panel's heading and warning card.
public enum ScrollCaptureStatus: Equatable, Sendable {
    /// The area is on screen and nothing has scrolled yet.
    case ready
    /// Frames are lining up and the image is growing.
    case live
    /// The content moved so far in one go that nothing in the new frame matches the last one.
    case tooFar
    /// Something in the area keeps changing in place, such as a video, so frames can't be lined up.
    case changing
    /// The area is blank or repeats, so the movement can't be told.
    case notEnough
    /// The image is as big as Shot can stitch; what's captured is kept.
    case sizeLimit

    /// The heading at the top of the panel.
    public var heading: String {
        switch self {
        case .ready: String(localized: "Start scrolling")
        case .live, .tooFar, .changing, .notEnough: String(localized: "Keep scrolling")
        case .sizeLimit: String(localized: "Full size")
        }
    }

    /// The line under the heading.
    public var detail: String {
        switch self {
        case .ready: String(localized: "Scroll the content in any direction.")
        case .live, .tooFar, .changing, .notEnough: String(localized: "Scroll in any direction. Hatched parts aren't captured yet.")
        case .sizeLimit: String(localized: "The image is as big as Shot can stitch. Press Return to save it.")
        }
    }

    /// What the warning card says when something needs attention; nothing while the capture is going well.
    public var warning: (title: String, advice: String)? {
        switch self {
        case .tooFar: (String(localized: "Scrolled too far"), String(localized: "Scroll back a little and carry on."))
        case .changing: (String(localized: "Can't line up"), String(localized: "Something in the area keeps changing. Pause it or scroll past it."))
        case .notEnough: (String(localized: "Nothing to line up"), String(localized: "Include some text or an image, or pick another area."))
        case .ready, .live, .sizeLimit: nil
        }
    }

    /// Whether the panel shows a warning card.
    public var isWarning: Bool {
        switch self {
        case .tooFar, .changing, .notEnough: true
        case .ready, .live, .sizeLimit: false
        }
    }
}

/// The limits a scrolling capture's image stays within, so memory stays bounded however long it runs.
public struct ScrollCaptureLimits: Sendable {
    /// Pixels on either side.
    public var maxSide: Int
    /// Pixels in all.
    public var maxPixels: Int

    public init(maxSide: Int, maxPixels: Int) {
        self.maxSide = maxSide
        self.maxPixels = maxPixels
    }

    /// 30,000 pixels a side, and 100 million in all: 400 MB of RGBA.
    public static let standard = ScrollCaptureLimits(maxSide: 30_000, maxPixels: 100_000_000)
}

/// Where the scrolling capture panel goes: beside the area, never over it, unless the area leaves no room anywhere.
public enum ScrollCapturePanelPlacement {
    /// The origin of a panel of `size` next to `region`, within `visible`; all in AppKit space. To the right of the
    /// area if it fits, else to the left, below, or above, in that order, lined up with the area's top or left edge.
    /// When the area leaves no room on any side, the panel sits inside its bottom-right corner.
    public static func origin(for size: CGSize, region: CGRect, visible: CGRect, gap: CGFloat = 14, margin: CGFloat = 8) -> CGPoint {
        let room = visible.insetBy(dx: margin, dy: margin)
        func clamp(_ origin: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(origin.x, room.minX), room.maxX - size.width),
                y: min(max(origin.y, room.minY), room.maxY - size.height)
            )
        }
        let top = region.maxY - size.height
        if region.maxX + gap + size.width <= room.maxX {
            return clamp(CGPoint(x: region.maxX + gap, y: top))
        }
        if region.minX - gap - size.width >= room.minX {
            return clamp(CGPoint(x: region.minX - gap - size.width, y: top))
        }
        if region.minY - gap - size.height >= room.minY {
            return clamp(CGPoint(x: region.minX, y: region.minY - gap - size.height))
        }
        if region.maxY + gap + size.height <= room.maxY {
            return clamp(CGPoint(x: region.minX, y: region.maxY + gap))
        }
        return clamp(CGPoint(x: region.maxX - gap - size.width, y: region.minY + gap))
    }
}
