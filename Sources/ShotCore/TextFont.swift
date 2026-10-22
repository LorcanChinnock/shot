import Foundation

/// The system's interface font at `size` points, bold or regular.
public struct TextFont: Hashable, Sendable {
    public var size: CGFloat
    public var bold: Bool

    public init(size: CGFloat, bold: Bool = false) {
        self.size = size
        self.bold = bold
    }
}

public struct TextMetrics: Equatable, Sendable {
    public var ascent: CGFloat
    public var descent: CGFloat
    public var leading: CGFloat

    public init(ascent: CGFloat, descent: CGFloat, leading: CGFloat) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
    }

    /// The distance from one baseline to the next, rounded up to a whole point.
    public var lineHeight: CGFloat { (ascent + descent + leading).rounded(.up) }
}
