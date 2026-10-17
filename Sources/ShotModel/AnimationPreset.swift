import Foundation

/// One-click animations that fill in keyframes.
public enum AnimationPreset: String, CaseIterable, Sendable {
    case fadeIn, fadeOut, pop, slideIn, drawOn

    /// Whether it needs something that can be drawn a bit at a time: an arrow, line or pen stroke.
    public var needsStroke: Bool { self == .drawOn }

    /// Whether it animates the end of the clip rather than the start.
    public var playsAtEnd: Bool { self == .fadeOut }
}
