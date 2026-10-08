import CoreGraphics

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

    public var label: String {
        switch self {
        case .free: "Free"
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

    /// The next ratio in the cycle, wrapping around; `backward` steps the other way.
    public func next(backward: Bool = false) -> AspectRatio {
        let all = Self.allCases
        let index = all.firstIndex(of: self)! + (backward ? all.count - 1 : 1)
        return all[index % all.count]
    }
}
