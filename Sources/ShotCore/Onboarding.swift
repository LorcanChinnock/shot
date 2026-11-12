/// A step of the welcome window.
public enum OnboardingStep: Sendable {
    /// Screen Recording access, which every capture needs.
    case permission
    /// Accessibility access, which only capturing just a browser's page needs. It can be skipped.
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

    /// The steps the welcome window shows at launch, or after a capture fails: for someone new, Screen Recording access
    /// while it's missing, then setup and Try it; for everyone else, only Screen Recording access while it's missing.
    /// Accessibility isn't asked for here: only capturing a browser's page needs it, and turning that setting on asks for it then.
    public func steps(hasPermission: Bool, hasAccessibility: Bool) -> [OnboardingStep] {
        switch self {
        case .new: (hasPermission ? [] : [.permission]) + [.setup, .tryIt]
        case .done: hasPermission ? [] : [.permission]
        }
    }

    /// The steps the welcome window shows when it's opened again with `shot://welcome`, which also offers
    /// Accessibility to anyone who wants browser pages set up ahead of time.
    public static func replaySteps(hasPermission: Bool, hasAccessibility: Bool) -> [OnboardingStep] {
        access(hasPermission: hasPermission, hasAccessibility: hasAccessibility) + [.setup, .tryIt]
    }

    private static func access(hasPermission: Bool, hasAccessibility: Bool) -> [OnboardingStep] {
        (hasPermission ? [] : [.permission]) + (hasAccessibility ? [] : [.accessibility])
    }
}

/// One step in the welcome window's title bar, with whether it's done, the one showing, or still to come.
public struct OnboardingIndicatorItem: Equatable, Sendable {
    public enum State: Sendable {
        case done, current, upcoming
    }

    public let step: OnboardingStep
    public let state: State

    public init(step: OnboardingStep, state: State) {
        self.step = step
        self.state = state
    }

    /// The steps the title bar lists. Screen Recording access always comes first, ticked when the window doesn't ask for it,
    /// so someone back after the relaunch sees what they've done. The step showing is ticked once it's `finished`, such as
    /// Try it after the first capture. A window with one step lists none.
    public static func items(steps: [OnboardingStep], current: Int, finished: Bool) -> [OnboardingIndicatorItem] {
        let granted = !steps.contains(.permission)
        let all = (granted ? [.permission] : []) + steps
        guard all.count > 1 else {
            return []
        }
        let showing = current + (granted ? 1 : 0)
        return all.enumerated().map { index, step in
            let state: State = index < showing || (index == showing && finished) ? .done : index == showing ? .current : .upcoming
            return OnboardingIndicatorItem(step: step, state: state)
        }
    }
}
