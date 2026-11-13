import CoreGraphics
import Foundation

/// A stretch of text in one size, `length` UTF-16 code units long, as `NSString` and Core Text count them.
public struct TextRun: Equatable, Sendable {
    public var length: Int
    public var size: CGFloat

    public init(length: Int, size: CGFloat) {
        self.length = length
        self.size = size
    }
}

/// The size of each part of a text annotation's or note's text, in image pixels, run by run from its start. The runs
/// cover the text exactly; none is empty, and no two side by side share a size.
public struct TextRuns: Equatable, Sendable {
    public private(set) var runs: [TextRun]

    /// Sizes closer than this are the same size.
    static let tolerance: CGFloat = 0.001

    public init(_ runs: [TextRun]) {
        var merged: [TextRun] = []
        for run in runs where run.length > 0 {
            if let last = merged.last, abs(last.size - run.size) < Self.tolerance {
                merged[merged.count - 1].length += run.length
            } else {
                merged.append(run)
            }
        }
        self.runs = merged
    }

    /// `length` code units all in `size`.
    public init(length: Int, size: CGFloat) {
        self.init([TextRun(length: length, size: size)])
    }

    public var length: Int { runs.reduce(0) { $0 + $1.length } }

    /// True when the whole text is one size, or there's none.
    public var isUniform: Bool { runs.count <= 1 }

    /// The size of the largest part; `nil` for no text.
    public var largest: CGFloat? { runs.map(\.size).max() }

    /// The runs within `range`, cut to fit it.
    public func runs(in range: Range<Int>) -> [TextRun] {
        var start = 0
        var slices: [TextRun] = []
        for run in runs {
            let end = start + run.length
            let low = max(start, range.lowerBound), high = min(end, range.upperBound)
            if low < high {
                slices.append(TextRun(length: high - low, size: run.size))
            }
            start = end
        }
        return slices
    }

    /// True when `other` has the same runs, each within a hundredth of a pixel of the same size.
    public func isClose(to other: TextRuns) -> Bool {
        runs.count == other.runs.count && zip(runs, other.runs).allSatisfy { $0.length == $1.length && abs($0.size - $1.size) < 0.01 }
    }

    /// The size of the code unit at `index`; `nil` past the end.
    public func size(at index: Int) -> CGFloat? {
        guard index >= 0 else {
            return nil
        }
        var start = 0
        for run in runs {
            if index < start + run.length {
                return run.size
            }
            start += run.length
        }
        return nil
    }

    /// The size text typed at `offset` takes, as a Mac text field gives it: the size before it, or at the very start,
    /// the first; `nil` for no text.
    public func caretSize(at offset: Int) -> CGFloat? {
        size(at: min(offset, length) - 1) ?? runs.first?.size
    }

    /// The one size all of `range` is in; `nil` when it holds more than one. An empty range has the size text typed
    /// there takes.
    public func uniformSize(in range: Range<Int>) -> CGFloat? {
        guard !range.isEmpty else {
            return caretSize(at: range.lowerBound)
        }
        let sizes = runs(in: range).map(\.size)
        guard let first = sizes.first, sizes.allSatisfy({ abs($0 - first) < Self.tolerance }) else {
            return nil
        }
        return first
    }

    /// The largest size within `range`; `nil` when it's empty.
    public func largest(in range: Range<Int>) -> CGFloat? {
        runs(in: range).map(\.size).max()
    }

    /// `range` replaced by `count` code units, which take the size of what's before the range, or at the very start,
    /// what's after it, as typing does; `fallback` when there's no text either side.
    public func replacing(_ range: Range<Int>, withCount count: Int, fallback: CGFloat) -> TextRuns {
        let range = clamped(range)
        let size = size(at: range.lowerBound - 1) ?? size(at: range.upperBound) ?? fallback
        return TextRuns(runs(in: 0..<range.lowerBound) + [TextRun(length: count, size: size)] + runs(in: range.upperBound..<length))
    }

    /// The runs for `new`, made from these, which cover `old`: the text the two share at their start and end keeps its
    /// sizes, and what's typed between takes the size before it.
    public func edited(from old: String, to new: String, fallback: CGFloat) -> TextRuns {
        let before = Array(old.utf16), after = Array(new.utf16)
        var prefix = 0
        while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < before.count - prefix, suffix < after.count - prefix, before[before.count - 1 - suffix] == after[after.count - 1 - suffix] {
            suffix += 1
        }
        return replacing(prefix..<(before.count - suffix), withCount: after.count - prefix - suffix, fallback: fallback)
    }

    /// `range` all in `size`, the rest as it was.
    public func setting(_ size: CGFloat, in range: Range<Int>) -> TextRuns {
        let range = clamped(range)
        return TextRuns(runs(in: 0..<range.lowerBound) + [TextRun(length: range.count, size: size)] + runs(in: range.upperBound..<length))
    }

    /// Each size within `range` passed through `transform`, the rest as they were.
    public func mapping(in range: Range<Int>, _ transform: (CGFloat) -> CGFloat) -> TextRuns {
        let range = clamped(range)
        let inside = runs(in: range).map { TextRun(length: $0.length, size: transform($0.size)) }
        return TextRuns(runs(in: 0..<range.lowerBound) + inside + runs(in: range.upperBound..<length))
    }

    private func clamped(_ range: Range<Int>) -> Range<Int> {
        let low = min(max(range.lowerBound, 0), length)
        return low..<min(max(range.upperBound, low), length)
    }
}
