import Foundation

/// The redesign's moments of delight (spec › Motion): how long each plays, and what Reduce Motion turns it into. Each
/// plays only after its work is done, so nothing waits for one.
public enum Moment: CaseIterable, Sendable {
    /// An ink button sinks into its drop.
    case press
    /// The viewfinder's corners snap in over a capture, after it's copied.
    case viewfinderSnap
    /// A toast's tick draws itself.
    case tick
    /// A new counter pops in with a small overshoot.
    case markLand
    /// A panel or toast springs in.
    case panelArrive
    /// The menu bar's countdown digit flips.
    case countdownFlip
    /// The countdown panel's ring drains a second's worth, once a second.
    case countdownRing
    /// The menu bar's recording mark breathes.
    case recordingPulse
    /// A click's ring fades out once it has held for `ClickRing.hold`.
    case clickRing

    /// What Reduce Motion plays instead.
    public enum Reduced: Sendable {
        /// A fade of `Moment.reducedFade`.
        case fade
        /// Nothing: the end state shows at once.
        case none
    }

    /// The one length every reduced moment fades over.
    public static let reducedFade: TimeInterval = 0.12

    /// How long it plays, or one loop of it for the ambient ones.
    public var duration: TimeInterval {
        switch self {
        case .press: 0.08
        case .viewfinderSnap: 0.18
        case .tick: 0.24
        case .markLand: 0.2
        case .panelArrive: 0.24
        case .countdownFlip: 0.16
        case .countdownRing: 1
        case .recordingPulse: 1.6
        case .clickRing: 0.24
        }
    }

    /// Loops that tick with real time rather than answering an action, so they may run longer than 300 ms.
    public var isAmbient: Bool {
        switch self {
        case .countdownRing, .recordingPulse: true
        case .press, .viewfinderSnap, .tick, .markLand, .panelArrive, .countdownFlip, .clickRing: false
        }
    }

    public var reduced: Reduced {
        switch self {
        case .viewfinderSnap, .tick, .panelArrive: .fade
        case .press, .markLand, .countdownFlip, .countdownRing, .recordingPulse, .clickRing: .none
        }
    }

    /// The scale of a counter landing at `progress`, from 0 to 1: it grows to 122%, then settles at 100%.
    public static func popScale(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        let peak = 1.22
        let turn = 0.6
        if t < turn {
            let u = t / turn
            // Ease out, starting a little above nothing so the mark is never drawn at zero size.
            return 0.05 + (peak - 0.05) * (1 - (1 - u) * (1 - u))
        }
        let u = (t - turn) / (1 - turn)
        return peak - (peak - 1) * (u * u * (3 - 2 * u))
    }

    /// The menu bar digit at `progress` through a flip from 0 to 1: the old digit folds flat in the first half, and the new
    /// one unfolds in the second. `height` is the digit's vertical scale.
    public static func flip(_ progress: Double) -> (showsPrevious: Bool, height: Double) {
        let t = min(max(progress, 0), 1)
        return t < 0.5 ? (true, 1 - t * 2) : (false, t * 2 - 1)
    }

    /// The ring that breathes out of the recording mark at `phase` through one loop, from 0 to 1: it grows from the mark
    /// to full size and fades out over the first 60%, then rests. `spread` runs 0 to 1, and `opacity` from 0.5 to 0.
    public static func pulse(_ phase: Double) -> (spread: Double, opacity: Double) {
        let t = phase - phase.rounded(.down)
        guard t < 0.6 else {
            return (1, 0)
        }
        let u = t / 0.6
        return (1 - (1 - u) * (1 - u), 0.5 * (1 - u))
    }
}
