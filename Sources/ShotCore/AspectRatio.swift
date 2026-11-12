import CoreGraphics
import Foundation

/// The shape an area selection is held to while dragging; Tab steps through them.
public enum AspectRatio: CaseIterable, Sendable {
    case free, square, fourThree, threeTwo, sixteenNine

    /// Long side over short side, or `nil` when unconstrained.
    public var value: CGFloat? {
        switch self {
        case .free: nil
        case .square: 1
        case .fourThree: 4.0 / 3
        case .threeTwo: 3.0 / 2
        case .sixteenNine: 16.0 / 9
        }
    }

    /// The next ratio in the cycle, wrapping around; `backward` steps the other way.
    public func next(backward: Bool = false) -> AspectRatio {
        let all = Self.allCases
        let index = all.firstIndex(of: self)! + (backward ? all.count - 1 : 1)
        return all[index % all.count]
    }
}

extension AspectRatio {
    public var label: String {
        switch self {
        case .free: String(localized: "Free")
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        }
    }

    /// The label with its sides swapped when `portrait`, e.g. 9:16.
    public func label(portrait: Bool) -> String {
        portrait ? label.split(separator: ":").reversed().joined(separator: ":") : label
    }
}

/// The ratio an area is held to and which way it's turned, as the capture bar's Ratio button and menu show it. Dragging
/// keeps it as set, so the area always matches the button.
public struct AreaShape: Equatable, Sendable {
    public var ratio: AspectRatio
    public var portrait: Bool

    public init(ratio: AspectRatio = .free, portrait: Bool = false) {
        self.ratio = ratio
        self.portrait = portrait
    }

    /// Width over height, or `nil` when free.
    public var widthOverHeight: CGFloat? {
        ratio.value.map { portrait ? 1 / $0 : $0 }
    }

    /// "16:9", "9:16" when turned, or "Free".
    public var label: String {
        ratio.label(portrait: portrait && turns)
    }

    /// Only a ratio with a long side can turn.
    public var turns: Bool {
        ratio != .free && ratio != .square
    }

    public mutating func turn() {
        if turns {
            portrait.toggle()
        }
    }
}
