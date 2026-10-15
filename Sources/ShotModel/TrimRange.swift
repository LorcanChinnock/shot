import Foundation

public enum TrimHandle: Sendable {
    case start, end
}

/// The part of a recording to keep, in seconds.
public struct TrimRange: Equatable, Sendable {
    /// Shortest range the handles can make, so they never cross.
    public static let minimumLength: Double = 0.1

    public private(set) var start: Double
    public private(set) var end: Double

    public init(duration: Double) {
        start = 0
        end = max(0, duration)
    }

    /// Clamps to `0...duration` and orders the ends.
    public init(start: Double, end: Double, duration: Double) {
        let clamped = [start, end].map { min(max($0, 0), max(0, duration)) }
        self.start = clamped.min()!
        self.end = clamped.max()!
    }

    public var length: Double { end - start }

    public func isFull(duration: Double) -> Bool {
        start <= 0 && end >= duration
    }

    /// Drags `handle` to `time`, keeping the range inside the video and at least `minimumLength` long.
    public func moving(_ handle: TrimHandle, to time: Double, duration: Double) -> TrimRange {
        guard duration > Self.minimumLength else {
            return self
        }
        var moved = self
        switch handle {
        case .start:
            moved.start = min(max(time, 0), end - Self.minimumLength)
        case .end:
            moved.end = max(min(time, duration), start + Self.minimumLength)
        }
        return moved
    }

    /// Moves both handles by `delta`, keeping the length, and stops at either end of the video.
    public func sliding(by delta: Double, duration: Double) -> TrimRange {
        let shift = min(max(delta, -start), duration - start)
        var moved = self
        moved.start += shift
        moved.end += shift
        return moved
    }

    /// Where Play begins: the playhead if it's inside the range, otherwise the in point.
    /// Within `endTolerance` of the out point counts as finished, since playback can stop a hair short of it.
    public func playbackStart(from current: Double, endTolerance: Double = 0.01) -> Double {
        current >= start && current < end - endTolerance ? current : start
    }
}

public enum Timecode {
    /// `m:ss.cc`, rounding down so the out point never reads past the end.
    public static func string(_ seconds: Double) -> String {
        let hundredths = Int((max(0, seconds) * 100).rounded(.down))
        let minutes = hundredths / 6000
        let secs = hundredths / 100 % 60
        return "\(minutes):" + String(format: "%02d.%02d", secs, hundredths % 100)
    }
}

/// Maps a recording's time onto a horizontal strip of `width` points starting at `minX`.
/// The start handle sits left of the in point and the end handle right of the out point.
public struct TrimTimeline: Sendable {
    public static let handleWidth: CGFloat = 12
    /// Extra reach around a handle, so a thin one is still easy to grab.
    public static let slop: CGFloat = 4

    public let duration: Double
    public let minX: CGFloat
    public let width: CGFloat

    public init(duration: Double, minX: CGFloat, width: CGFloat) {
        self.duration = duration
        self.minX = minX
        self.width = width
    }

    public func x(for time: Double) -> CGFloat {
        guard duration > 0 else {
            return minX
        }
        return minX + width * CGFloat(min(max(time, 0), duration) / duration)
    }

    public func time(at x: CGFloat) -> Double {
        guard width > 0 else {
            return 0
        }
        return duration * Double(min(max((x - minX) / width, 0), 1))
    }

    /// The handle under `x`, the nearer one when both are in reach.
    public func handle(at x: CGFloat, range: TrimRange) -> TrimHandle? {
        let startX = self.x(for: range.start), endX = self.x(for: range.end)
        let toStart = distance(from: x, to: startX - Self.handleWidth...startX)
        let toEnd = distance(from: x, to: endX...endX + Self.handleWidth)
        guard min(toStart, toEnd) <= Self.slop else {
            return nil
        }
        return toStart <= toEnd ? .start : .end
    }

    private func distance(from x: CGFloat, to span: ClosedRange<CGFloat>) -> CGFloat {
        x < span.lowerBound ? span.lowerBound - x : max(0, x - span.upperBound)
    }

    /// How many frames of `aspectRatio` (width / height) it takes to fill the strip.
    public static func thumbnailCount(width: CGFloat, height: CGFloat, aspectRatio: CGFloat) -> Int {
        let frameWidth = height * aspectRatio
        guard frameWidth > 0 else {
            return 1
        }
        return max(1, Int((width / frameWidth).rounded(.up)))
    }

    /// The midpoint of each of `count` equal slots.
    public func thumbnailTimes(count: Int) -> [Double] {
        (0..<max(1, count)).map { duration * (Double($0) + 0.5) / Double(max(1, count)) }
    }
}
