import Foundation

/// How long a recording has run, leaving out paused stretches, and which stretches of it are muted.
public struct RecordingTimeline: Sendable {
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?
    private var mutedSince: TimeInterval?
    /// Stretches of the recording, in recorded seconds, whose audio is silenced when the segments are joined.
    public private(set) var mutes = CutList()

    public init() {}

    public var isMuted: Bool { mutedSince != nil }

    public func elapsed(at date: Date) -> TimeInterval {
        accumulated + (runningSince.map { date.timeIntervalSince($0) } ?? 0)
    }

    public mutating func run(at date: Date) {
        runningSince = date
    }

    public mutating func hold(at date: Date) {
        accumulated = elapsed(at: date)
        runningSince = nil
    }

    public mutating func toggleMute(at date: Date) {
        if isMuted {
            endMute(at: date)
        } else {
            mutedSince = elapsed(at: date)
        }
    }

    /// Closes a mute in progress, so it ends with the recording.
    public mutating func endMute(at date: Date) {
        if let mutedSince {
            mutes = mutes.adding(mutedSince..<elapsed(at: date))
        }
        mutedSince = nil
    }
}
