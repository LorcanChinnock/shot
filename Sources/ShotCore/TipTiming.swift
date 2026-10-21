/// When hover tips appear: the first after the pointer rests on a control for a while, then at once as it moves on to
/// neighbouring controls, until it has been off every tipped control for `warmWindow`.
public struct TipTiming {
    public static let coldDelay: Duration = .seconds(1)
    public static let warmWindow: Duration = .milliseconds(500)

    private var hovered = 0
    private var leftAt: ContinuousClock.Instant?
    private var warm = false

    public init() {}

    /// How long the pointer has to rest on a control it just entered before its tip shows.
    public var delay: Duration {
        warm ? .zero : Self.coldDelay
    }

    public mutating func entered(at now: ContinuousClock.Instant) {
        if hovered == 0, let leftAt, leftAt.duration(to: now) >= Self.warmWindow {
            warm = false
        }
        hovered += 1
    }

    public mutating func left(at now: ContinuousClock.Instant) {
        hovered = max(hovered - 1, 0)
        if hovered == 0 {
            leftAt = now
        }
    }

    public mutating func shown() {
        warm = true
    }
}
