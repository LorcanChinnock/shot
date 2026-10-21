import Foundation

/// How long a recording has been recording, pauses left out, which is how far into the saved video it is. Times are
/// seconds on any clock that only goes forward. Each stretch counts the time it's recorded for, or the length its
/// segment turned out to be, when that's known, so the stretches after it line up with the video.
public struct RecordingClock: Equatable, Sendable {
    /// The time recorded before the stretch under way, or all of it while paused.
    private var recorded: Double = 0
    /// When the stretch under way started, and how much it had recorded by then, or `nil` while paused.
    private var stretch: (since: Double, offset: Double)?

    /// A clock that started recording at `start`, having recorded `offset` seconds by then.
    public init(start: Double, offset: Double = 0) {
        stretch = (start, offset)
    }

    public var isPaused: Bool { stretch == nil }

    /// Stops counting at `time`, if it's counting, counting the stretch as `length` seconds when its segment is known to
    /// be that long.
    public mutating func pause(at time: Double, length: Double? = nil) {
        if stretch != nil {
            recorded += length ?? current(at: time)
            stretch = nil
        }
    }

    /// Counts again from `time`, having recorded `offset` seconds of the new stretch by then, if it's paused.
    public mutating func resume(at time: Double, offset: Double = 0) {
        if stretch == nil {
            stretch = (time, offset)
        }
    }

    /// The time recorded by `time`.
    public func elapsed(at time: Double) -> Double {
        recorded + current(at: time)
    }

    private func current(at time: Double) -> Double {
        stretch.map { $0.offset + max(0, time - $0.since) } ?? 0
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.recorded == rhs.recorded && lhs.stretch?.since == rhs.stretch?.since && lhs.stretch?.offset == rhs.stretch?.offset
    }
}
