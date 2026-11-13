import CoreGraphics
import Foundation

/// Where the capture bar's buttons and dividers go, from Foundations › Capture bar: 6 pt padding, 4 pt between buttons,
/// and a 1 pt divider with 4 pt either side between groups. Positions run from the bar's leading edge; a group with no
/// buttons is left out, so it draws no divider.
public struct CaptureBarLayout: Equatable, Sendable {
    public static let padding: CGFloat = 6
    public static let gap: CGFloat = 4
    public static let dividerMargin: CGFloat = 4

    /// The frame of each button, group by group, inside a bar whose origin is zero.
    public let frames: [[CGRect]]
    /// The x of each divider's left edge.
    public let dividers: [CGFloat]
    public let size: CGSize

    /// `groups` holds each group's button widths, and every button is `height` tall.
    public init(groups: [[CGFloat]], height: CGFloat) {
        var frames: [[CGRect]] = []
        var dividers: [CGFloat] = []
        var x = Self.padding
        for group in groups where !group.isEmpty {
            if !frames.isEmpty {
                // The divider sits in the gap, with its own margin either side.
                x += Self.dividerMargin
                dividers.append(x)
                x += 1 + Self.dividerMargin + Self.gap
            }
            var row: [CGRect] = []
            for width in group {
                row.append(CGRect(x: x, y: Self.padding, width: width, height: height))
                x += width + Self.gap
            }
            frames.append(row)
        }
        let width = frames.isEmpty ? Self.padding * 2 : x - Self.gap + Self.padding
        self.frames = frames
        self.dividers = dividers
        size = CGSize(width: width, height: height + Self.padding * 2)
    }
}
