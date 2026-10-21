import Foundation

/// Takes screenshots where Shot has no app to take them: lists the displays and windows, and captures a display, a
/// window or an area. `shot serve` answers agents through one on Linux, chosen by the session, X11's or the desktop
/// portal's. The Mac app captures on its own and doesn't use it. Coordinates are in points, with the origin at the top
/// left of the first display and y growing downwards, and images come back at the display's scale.
public protocol ScreenCapturer: Sendable {
    /// What it's called in `shot serve`'s status, such as `x11`, or `none`.
    var name: String { get }
    /// What this session can't do, each with why, such as a window captured without asking on Wayland.
    var limits: [ScreenCapability: String] { get }

    /// The displays, the first being the main one.
    func displays() async throws(ShotCommandError) -> [ScreenDisplay]
    /// The windows on screen, front to back.
    func windows() async throws(ShotCommandError) -> [ScreenWindow]
    func capture(display: ScreenDisplay) async throws(ShotCommandError) -> Bitmap
    /// The window alone, without whatever covers it.
    func capture(window: ScreenWindow) async throws(ShotCommandError) -> Bitmap
    /// What's on screen in `area`, which lies on one display.
    func capture(area: CGRect) async throws(ShotCommandError) -> Bitmap
    /// Why `windows()` leaves some windows out, such as Wayland's own, which it doesn't share; `nil` when it lists them
    /// all.
    var windowsNote: String? { get }
    /// Asks the user to pick a screen, window or area in the desktop's own dialog, and captures it, for a window this
    /// can't find or capture by itself; `nil` when the session has no such dialog.
    func capturePicked() async throws(ShotCommandError) -> Bitmap?
    /// What records `area`, which lies on one display, at `frameRate`, with the pointer drawn when `showsCursor`. Throws
    /// `.unavailable`, with the reason `limits` gives for `.record`, where this session can't record.
    func recordingSource(area: CGRect, frameRate: Int, showsCursor: Bool) throws(ShotCommandError) -> any RecordingSource
}

extension ScreenCapturer {
    public var windowsNote: String? { nil }
    public func capturePicked() async throws(ShotCommandError) -> Bitmap? { nil }
    public func recordingSource(area: CGRect, frameRate: Int, showsCursor: Bool) throws(ShotCommandError) -> any RecordingSource {
        throw .unavailable(limits[.record] ?? "Shot can't record this session.")
    }
}

/// What a `ScreenCapturer` may be unable to do in its session.
public enum ScreenCapability: String, CaseIterable, Sendable {
    case listWindows
    case captureDisplay
    case captureWindow
    case captureArea
    case record
}

/// A display, as `shot windows` lists it.
public struct ScreenDisplay: Equatable, Sendable {
    public var name: String
    /// In points.
    public var frame: CGRect
    /// Pixels a point.
    public var scale: Double

    public init(name: String, frame: CGRect, scale: Double = 1) {
        self.name = name
        self.frame = frame
        self.scale = scale
    }
}

/// A window on screen.
public struct ScreenWindow: Equatable, Sendable {
    /// Unique among the windows listed together, such as an X11 window ID.
    public var id: UInt32
    public var app: String
    public var title: String
    /// What names the app on this desktop, such as its X11 class or Wayland app ID, which agents pass as `bundleID`;
    /// empty when there's none.
    public var appID: String
    /// In points.
    public var frame: CGRect

    public init(id: UInt32, app: String, title: String, appID: String = "", frame: CGRect) {
        self.id = id
        self.app = app
        self.title = title
        self.appID = appID
        self.frame = frame
    }

    /// The window as `WindowMatch` finds and lists it.
    public var candidate: WindowMatch.Candidate {
        WindowMatch.Candidate(id: id, app: app, title: title, bundleID: appID, width: frame.width, height: frame.height)
    }
}
