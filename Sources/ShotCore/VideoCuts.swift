/// Sections cut out of a recording, in seconds: sorted, and merged where they overlap or touch.
/// What's left of a `TrimRange` once they're removed is what plays and exports.
public struct CutList: Equatable, Sendable {
    /// Kept sections shorter than this are dropped, since a 600 timescale can't hold them.
    static let shortestSection: Double = 1.0 / 600

    public private(set) var cuts: [Range<Double>] = []

    public init() {}

    public init(_ cuts: [Range<Double>]) {
        self = cuts.reduce(CutList()) { $0.adding($1) }
    }

    public var isEmpty: Bool { cuts.isEmpty }

    /// Adds `cut`, merging it with any cut it overlaps or touches.
    public func adding(_ cut: Range<Double>) -> CutList {
        guard !cut.isEmpty else {
            return self
        }
        var merged = cut
        var result = CutList()
        for existing in cuts {
            if existing.lowerBound <= merged.upperBound && merged.lowerBound <= existing.upperBound {
                merged = min(existing.lowerBound, merged.lowerBound)..<max(existing.upperBound, merged.upperBound)
            } else {
                result.cuts.append(existing)
            }
        }
        result.cuts.append(merged)
        result.cuts.sort { $0.lowerBound < $1.lowerBound }
        return result
    }

    /// Cuts the part of `selection` inside `range`; nil when that would leave less than
    /// `TrimRange.minimumLength` to play. A selection outside the range changes nothing.
    public func cutting(_ selection: Range<Double>, from range: TrimRange) -> CutList? {
        let cut = adding(selection.clamped(to: range.start..<range.end))
        return cut.allows(range) ? cut : nil
    }

    /// Whether `range` keeps at least `TrimRange.minimumLength` between these cuts.
    public func allows(_ range: TrimRange) -> Bool {
        keptLength(in: range) >= TrimRange.minimumLength - 1e-9
    }

    /// The sections of `range` these cuts leave, in order.
    public func kept(in range: TrimRange) -> [TrimRange] {
        var sections: [TrimRange] = []
        var start = range.start
        for cut in cuts where cut.upperBound > range.start && cut.lowerBound < range.end {
            if cut.lowerBound - start >= Self.shortestSection {
                sections.append(TrimRange(start: start, end: cut.lowerBound, duration: range.end))
            }
            start = max(start, cut.upperBound)
        }
        if range.end - start >= Self.shortestSection {
            sections.append(TrimRange(start: start, end: range.end, duration: range.end))
        }
        return sections
    }

    public func keptLength(in range: TrimRange) -> Double {
        kept(in: range).reduce(0) { $0 + $1.length }
    }

    public func cut(containing time: Double) -> Range<Double>? {
        cuts.first { $0.contains(time) }
    }

    /// The source time that plays `time` seconds into the result (before any speed change).
    public func sourceTime(at time: Double, in range: TrimRange) -> Double {
        let sections = kept(in: range)
        var remaining = max(0, time)
        for section in sections {
            if remaining < section.length {
                return section.start + remaining
            }
            remaining -= section.length
        }
        return sections.last?.end ?? range.end
    }

    /// Where playback stops: the end of the last kept section.
    public func playbackEnd(in range: TrimRange) -> Double {
        kept(in: range).last?.end ?? range.end
    }

    /// Where Play begins: like `TrimRange.playbackStart` over the kept sections, skipping to the end of a cut the playhead is in.
    public func playbackStart(from current: Double, in range: TrimRange, endTolerance: Double = 0.01) -> Double {
        let sections = kept(in: range)
        guard let first = sections.first, let last = sections.last else {
            return range.start
        }
        let start = TrimRange(start: first.start, end: last.end, duration: last.end).playbackStart(from: current, endTolerance: endTolerance)
        return cut(containing: start)?.upperBound ?? start
    }
}
