import CoreGraphics
import Foundation

/// The modes the capture bar offers (Foundations › Capture bar): the overlay's three targets, with a browser window's page
/// as a fourth. Browser is a window pick that takes just the page, so it maps onto `.window` with page-only on.
public enum CaptureBarMode: CaseIterable, Sendable {
    case area, window, screen, browser

    /// The mode the bar shows as picked for a target, and whether a browser window is being picked as just its page.
    public init(target: CaptureTarget, browserPage: Bool) {
        switch target {
        case .area: self = .area
        case .window: self = browserPage ? .browser : .window
        case .screen: self = .screen
        }
    }

    public var target: CaptureTarget {
        switch self {
        case .area: .area
        case .window, .browser: .window
        case .screen: .screen
        }
    }

    /// Whether picking this mode picks a browser window's page alone.
    public var picksPage: Bool { self == .browser }

    public var title: String {
        switch self {
        case .area, .window, .screen: target.title
        case .browser: String(localized: "Browser")
        }
    }

    /// The key that reaches this mode, shown in its tooltip. Tab steps through the targets, and B switches a window pick to its page.
    public var key: String {
        self == .browser ? "B" : "Tab"
    }
}

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
