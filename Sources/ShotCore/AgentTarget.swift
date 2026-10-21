import Foundation

/// What an agent points `capture` or `record` at: an open window, by words from it or by its app's bundle ID, or a
/// whole display, and optionally only part of it. The command line, the MCP tools and the agent socket all check it here.
public struct AgentTarget: Equatable, Sendable {
    /// The longest `waitStable` may be, in seconds, so a window that never settles can't hold a request for long.
    public static let maximumWaitStable: Double = 30
    /// What `--wait-stable` waits for at most, without a time of its own.
    public static let defaultWaitStable: Double = 5

    /// Words from the window's title or app, as `WindowMatch` reads them.
    public var window: String?
    /// The app whose window it is, such as `com.apple.iphonesimulator`; with `window`, the window of that app it names.
    public var bundleID: String?
    /// A whole display instead of a window, numbered from 1 as `shot windows` lists them.
    public var display: Int?
    /// Only this part, `[x, y, width, height]` in points from the window's or display's top-left corner.
    public var rect: [Double]?
    /// Leaves out the window's shadow, whatever Settings › Capture says.
    public var noShadow: Bool
    /// For a screenshot: waits up to this many seconds for the picture to stop changing first.
    public var waitStable: Double?

    public init(window: String? = nil, bundleID: String? = nil, display: Int? = nil, rect: [Double]? = nil, noShadow: Bool = false, waitStable: Double? = nil) {
        self.window = window
        self.bundleID = bundleID
        self.display = display
        self.rect = rect
        self.noShadow = noShadow
        self.waitStable = waitStable
    }

    /// Whether it names a window rather than a display.
    public var isWindow: Bool {
        display == nil
    }

    /// Why a recording can't wait for the window to settle.
    public static let waitStableIsForCapture = "can't wait for the window to settle; that's for a screenshot"

    /// What's wrong with the target, or `nil` when it can be used. Worded to follow the command's name, as in
    /// "capture needs a window …", and without flags, since the MCP tools spell them differently.
    public var problem: String? {
        let hasWindow = !(window ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let hasApp = !(bundleID ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        if let display {
            guard !hasWindow, !hasApp else {
                return "takes a window or a display, not both"
            }
            guard display >= 1 else {
                return "needs a display numbered from 1, as shot windows lists them"
            }
            guard !noShadow else {
                return "can leave out only a window's shadow; a display has none"
            }
        } else if !hasWindow, !hasApp {
            return "needs a window: words from its title or app, such as Simulator, its app's bundle ID, or a display"
        }
        if let rect, !Self.isRect(rect) {
            return "needs a rect of x, y, width and height in points, with x and y 0 or more and a width and height above 0"
        }
        if let waitStable, !(waitStable > 0 && waitStable <= Self.maximumWaitStable) {
            return "can wait for the window to settle for above 0 and at most \(Int(Self.maximumWaitStable)) seconds"
        }
        return nil
    }

    static func isRect(_ rect: [Double]) -> Bool {
        rect.count == 4 && rect.allSatisfy(\.isFinite) && rect[0] >= 0 && rect[1] >= 0 && rect[2] > 0 && rect[3] > 0
    }

    /// The part of `bounds` that `rect`, in points from its top-left, covers, in the same space as `bounds` (top-left
    /// origin); all of `bounds` without a rect, and `nil` when the rect is off it.
    public func area(in bounds: CGRect) -> CGRect? {
        guard let rect, rect.count == 4 else {
            return bounds
        }
        let x = Double(bounds.minX) + rect[0], y = Double(bounds.minY) + rect[1]
        return Self.clip(minX: x, minY: y, maxX: x + rect[2], maxY: y + rect[3], to: bounds)
    }

    /// The pixels of a `width` × `height` image at `scale` pixels a point that `rect` covers, whole and inside the
    /// image; the whole image without a rect, and `nil` when the rect is off it.
    public func pixels(width: Int, height: Int, scale: Double) -> CGRect? {
        let image = CGRect(x: 0, y: 0, width: width, height: height)
        guard let rect, rect.count == 4 else {
            return image
        }
        let minX = (rect[0] * scale).rounded(.down), minY = (rect[1] * scale).rounded(.down)
        let maxX = ((rect[0] + rect[2]) * scale).rounded(.up), maxY = ((rect[1] + rect[3]) * scale).rounded(.up)
        return Self.clip(minX: minX, minY: minY, maxX: maxX, maxY: maxY, to: image)
    }

    /// The rect between the edges, cut to `bounds`, or `nil` when less than a point of it is left.
    private static func clip(minX: Double, minY: Double, maxX: Double, maxY: Double, to bounds: CGRect) -> CGRect? {
        let left = max(minX, Double(bounds.minX)), top = max(minY, Double(bounds.minY))
        let right = min(maxX, Double(bounds.maxX)), bottom = min(maxY, Double(bounds.maxY))
        guard right - left >= 1, bottom - top >= 1 else {
            return nil
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The target as an agent's answer describes it when a rect was off it, such as `rect 10,10,5000,20`.
    public var rectText: String {
        "rect " + (rect ?? []).map { String(format: "%g", $0) }.joined(separator: ",")
    }
}

/// Waits for a window to stop changing before a screenshot, from small grayscale thumbnails taken a few times a second:
/// it's settled once one matches the one before, and gives up at its timeout, when the newest is taken anyway.
public struct StableWait: Sendable {
    public enum Verdict: Equatable, Sendable {
        case wait
        case settled
        case timedOut
    }

    /// How far apart two samples are taken, in seconds.
    public static let interval = 0.2
    /// The most two thumbnails may differ and still count as the same picture, from 0 to 1: a blinking caret or a
    /// clock's seconds changing in a corner shouldn't keep it waiting.
    public static let tolerance = 0.002

    public let timeout: Double
    private var previous: [UInt8]?

    public init(timeout: Double) {
        self.timeout = timeout
    }

    /// Adds the thumbnail taken `elapsed` seconds after the first, and says whether to keep waiting.
    public mutating func add(_ thumbnail: [UInt8], elapsed: Double) -> Verdict {
        defer { previous = thumbnail }
        if let previous, FramePicker.difference(previous, thumbnail) <= Self.tolerance {
            return .settled
        }
        return elapsed >= timeout ? .timedOut : .wait
    }
}
