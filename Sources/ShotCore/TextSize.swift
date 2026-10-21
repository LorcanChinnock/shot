import Foundation

/// How large Shot draws its own interface text, from Settings › General. macOS keeps its Accessibility › Text size
/// setting to the Apple apps that opt in, so Shot has its own. Captures and annotations are never scaled.
public enum TextSize: String, CaseIterable, Sendable {
    case standard, large, larger

    public var scale: Double {
        switch self {
        case .standard: 1
        case .large: 1.15
        case .larger: 1.3
        }
    }

    /// A font size at this text size, to the nearest half point so glyphs stay on whole pixels at 2×.
    public func points(_ size: Double) -> Double {
        (size * scale * 2).rounded() / 2
    }
}
