import CoreGraphics

public enum CameraBubbleSize: String, CaseIterable, Sendable {
    case small, medium, large

    public var diameter: CGFloat {
        switch self {
        case .small: 160
        case .medium: 220
        case .large: 300
        }
    }

    public var next: CameraBubbleSize {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// Largest size that still fits inside `region` with `inset` on each side, or `nil` if none fits.
    public static func fitting(_ preferred: CameraBubbleSize, in region: CGRect, inset: CGFloat) -> CameraBubbleSize? {
        let room = min(region.width, region.height) - inset * 2
        return allCases.reversed().first { $0.diameter <= preferred.diameter && $0.diameter <= room }
    }
}

public enum CameraBubbleLayout {
    /// Bottom-left corner of `region` (AppKit space, bottom-left origin), so the bubble lands inside the recording.
    public static func initialFrame(in region: CGRect, diameter: CGFloat, inset: CGFloat) -> CGRect {
        CGRect(x: region.minX + inset, y: region.minY + inset, width: diameter, height: diameter)
    }

    /// Keeps a resized bubble's center where it was.
    public static func resized(_ frame: CGRect, to diameter: CGFloat) -> CGRect {
        CGRect(x: frame.midX - diameter / 2, y: frame.midY - diameter / 2, width: diameter, height: diameter)
    }
}
