/// A step of the welcome window.
public enum OnboardingStep: Sendable {
    /// Screen Recording access, which every capture needs.
    case permission
    /// Accessibility access, which only Browser capture needs. It can be skipped.
    case accessibility
    /// The macOS screenshot keys and Open at login.
    case setup
    /// A first real capture.
    case tryIt
}

/// How far someone has got through the welcome window. Saved once a launch has worked it out, so it never has to be
/// guessed again.
public enum OnboardingProgress: String, Sendable {
    /// The setup step hasn't been answered yet, so Shot leaves macOS its screenshot keys.
    case new
    /// The setup step was answered or closed, or Shot was in use before the welcome window existed.
    case done

    /// The saved progress, or with none saved, `done` for someone who used Shot before the welcome window existed and
    /// `new` for a first launch.
    public init(saved: String?, hasSavedSettings: Bool) {
        self = saved.flatMap(Self.init(rawValue:)) ?? (hasSavedSettings ? .done : .new)
    }

    /// The steps the welcome window shows at launch, or after a capture fails: all of them for someone new, skipping
    /// each access step skipped once it's granted, and only Screen Recording access for everyone else, while it's missing.
    public func steps(hasPermission: Bool, hasAccessibility: Bool) -> [OnboardingStep] {
        switch self {
        case .new: Self.access(hasPermission: hasPermission, hasAccessibility: hasAccessibility) + [.setup, .tryIt]
        case .done: hasPermission ? [] : [.permission]
        }
    }

    /// The steps the welcome window shows when it's opened again from Settings or `shot://welcome`.
    public static func replaySteps(hasPermission: Bool, hasAccessibility: Bool) -> [OnboardingStep] {
        access(hasPermission: hasPermission, hasAccessibility: hasAccessibility) + [.setup, .tryIt]
    }

    private static func access(hasPermission: Bool, hasAccessibility: Bool) -> [OnboardingStep] {
        (hasPermission ? [] : [.permission]) + (hasAccessibility ? [] : [.accessibility])
    }
}
