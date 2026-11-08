import AppKit
import QuartzCore
import ShotCore
import SwiftUI

/// SwiftUI and AppKit animations for each `Moment`, with Reduce Motion's fade or nothing in place of movement. Views that
/// read `accessibilityReduceMotion` pass it in; code outside a view, such as a window controller, reads the system's.
@MainActor
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The animation for `moment`; nil when Reduce Motion shows its end state at once.
    static func animation(_ moment: Moment, reduceMotion: Bool = reduced) -> Animation? {
        if reduceMotion {
            return moment.reduced == .fade ? fade : nil
        }
        return switch moment {
        case .press, .countdownRing: .linear(duration: moment.duration)
        case .panelArrive: .spring(duration: moment.duration, bounce: 0.25)
        case .recordingPulse: .easeOut(duration: moment.duration).repeatForever(autoreverses: false)
        case .viewfinderSnap, .tick, .markLand, .countdownFlip, .clickRing: .easeOut(duration: moment.duration)
        }
    }

    /// Reduce Motion's stand-in for movement.
    static let fade = Animation.easeOut(duration: Moment.reducedFade)

    /// A panel arriving: a 240 ms spring with a small overshoot, or the fade.
    static var arrive: Animation { animation(.panelArrive) ?? fade }
    /// A panel leaving: as quick as arriving but without the bounce, so dismissing feels responsive.
    static var leave: Animation { reduced ? fade : .spring(duration: Moment.panelArrive.duration, bounce: 0) }

    /// The overshooting curve AppKit uses for a window springing in, close to `arrive`.
    static let arriveCurve = CAMediaTimingFunction(controlPoints: 0.34, 1.4, 0.64, 1)
}
