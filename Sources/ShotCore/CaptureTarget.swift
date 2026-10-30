import Foundation

/// What a screenshot or recording takes: a dragged-out area, one window, just the page of a browser window, or a whole
/// screen. Tab on the selection overlay steps through them.
public enum CaptureTarget: String, CaseIterable, Sendable {
    case area, window, browser, screen

    /// The next target, wrapping around; `backward` steps the other way.
    public func next(backward: Bool = false) -> CaptureTarget {
        let all = Self.allCases
        let index = all.firstIndex(of: self)! + (backward ? all.count - 1 : 1)
        return all[index % all.count]
    }

    public var title: String {
        switch self {
        case .area: String(localized: "Area")
        case .window: String(localized: "Window")
        case .browser: String(localized: "Browser")
        case .screen: String(localized: "Full Screen")
        }
    }
}

/// The wait before a capture or recording starts, chosen on the overlay each time. It starts off, so the quick path
/// never waits.
public enum CaptureDelay {
    /// Seconds in the order the overlay steps through them; 0 is off.
    public static let choices = [0] + ScreenshotTimer.delays

    /// The next choice, wrapping back to off after the longest.
    public static func next(after seconds: Int) -> Int {
        let index = choices.firstIndex(of: seconds) ?? 0
        return choices[(index + 1) % choices.count]
    }

    public static func label(_ seconds: Int) -> String {
        seconds == 0 ? String(localized: "Off") : String(localized: "\(seconds) s")
    }
}
