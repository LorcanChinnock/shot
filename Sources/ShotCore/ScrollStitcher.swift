import Foundation

/// Joins the frames of a scrolling area into one tall (or wide) image. Each frame is matched to the one before it to find
/// how far the content moved, and only the rows or columns not seen yet are appended. Rows that stay put between frames
/// (a sticky header or footer) are kept once, and scrolling back over content adds nothing.
///
/// The work is done on rows. A horizontal stitcher runs the same code on transposed bitmaps.
public struct ScrollStitcher: Sendable {
    public enum Axis: Sendable {
        case vertical
        case horizontal
    }

    public enum Outcome: Equatable, Sendable {
        /// The frame showed this many new pixels along the scroll direction, and they were added.
        case appended(Int)
        /// The frame showed nothing new: the content didn't move, or moved back over what was captured.
        case unchanged
        /// The content moved so far that the frame has no overlap with the last good one. Nothing was added, and the
        /// next frame is matched to the last good one, so scrolling back recovers.
        case tooFar
        /// Part of the frame changed without scrolling, such as a playing video. Nothing was added.
        case moving
        /// The image reached `maxLength`. Rows that fit were added, and later frames add nothing.
        case limit
    }

    /// The longest image Shot stitches, in pixels along the scroll direction.
    public static let defaultMaxLength = 30_000

    public let axis: Axis
    public let maxLength: Int

    /// Rows the frames may differ in and still count as matching, as a share of the overlap: a blinking caret or a
    /// hover highlight shouldn't stop the stitch.
    private static let tolerance = 0.03
    /// Share of the moving part that two frames must overlap by, so a match rests on enough rows to be trusted.
    private static let minOverlapShare = 8

    private let width: Int
    private let frameRows: Int
    private let first: Bitmap
    private var last: Bitmap
    private var lastHashes: [UInt64]
    /// Set by the first frame that differs from the one before: the rows at the top and bottom that didn't change.
    private var split: (header: Int, footer: Int)?
    private var header = Data()
    private var footer = Data()
    private var body = Data()
    private var bodyRows = 0
    /// Where the last frame's moving part starts in `body`; negative when it is above the first frame's.
    private var position = 0
    private var full = false
    private let scale: CGFloat

    public init(first frame: Bitmap, axis: Axis = .vertical, maxLength: Int = ScrollStitcher.defaultMaxLength) {
        self.axis = axis
        self.maxLength = maxLength
        scale = frame.scale
        let oriented = axis == .vertical ? frame : frame.transposed()
        first = oriented
        last = oriented
        width = oriented.width
        frameRows = oriented.height
        lastHashes = Self.rowHashes(oriented)
    }

    /// The pixels stitched so far along the scroll direction.
    public var length: Int {
        split == nil ? frameRows : header.count / (width * 4) + bodyRows + footer.count / (width * 4)
    }

    /// The image's width and height in pixels so far.
    public var size: (width: Int, height: Int) {
        axis == .vertical ? (width, length) : (length, width)
    }

    /// The image so far.
    public var result: Bitmap {
        guard split != nil else {
            return axis == .vertical ? first : first.transposed()
        }
        let stitched = Bitmap(width: width, height: length, scale: scale, pixels: header + body + footer)!
        return axis == .vertical ? stitched : stitched.transposed()
    }

    public mutating func add(_ frame: Bitmap) -> Outcome {
        if full {
            return .limit
        }
        let current = axis == .vertical ? frame : frame.transposed()
        guard current.width == width, current.height == frameRows else {
            return .moving
        }
        let hashes = Self.rowHashes(current)
        if hashes == lastHashes {
            return .unchanged
        }
        if split == nil, !beginMovingPart(with: hashes) {
            return .moving
        }
        guard let parts = split else {
            return .moving
        }
        let (h, f) = (parts.header, parts.footer)
        let n = frameRows - h - f
        let before = Array(lastHashes[h..<h + n])
        let after = Array(hashes[h..<h + n])
        guard let shift = Self.shift(from: before, to: after) else {
            return Self.nearestMismatch(before, after) <= 0.5 ? .moving : .tooFar
        }
        last = current
        lastHashes = hashes
        position += shift
        var fresh = position + n - bodyRows
        guard fresh > 0 else {
            return .unchanged
        }
        let start = h + n - fresh
        let room = maxLength - h - f - bodyRows
        if fresh > room {
            fresh = max(room, 0)
            full = true
        }
        append(rows: start..<start + fresh, of: current)
        return full ? .limit : .appended(fresh)
    }

    /// Finds the unchanged rows at the top and bottom of the first two different frames and starts the moving part.
    /// `false` when too little is left to match.
    private mutating func beginMovingPart(with hashes: [UInt64]) -> Bool {
        var h = 0
        while h < frameRows, hashes[h] == lastHashes[h] {
            h += 1
        }
        var f = 0
        while f < frameRows - h, hashes[frameRows - 1 - f] == lastHashes[frameRows - 1 - f] {
            f += 1
        }
        let n = frameRows - h - f
        guard n >= Self.minOverlapShare else {
            return false
        }
        split = (h, f)
        header = rows(0..<h, of: first)
        footer = rows(frameRows - f..<frameRows, of: first)
        body = rows(h..<h + n, of: first)
        bodyRows = n
        position = 0
        return true
    }

    private mutating func append(rows range: Range<Int>, of frame: Bitmap) {
        body.append(rows(range, of: frame))
        bodyRows += range.count
    }

    private func rows(_ range: Range<Int>, of frame: Bitmap) -> Data {
        let rowBytes = width * 4
        let start = frame.pixels.startIndex
        return frame.pixels.subdata(in: start + range.lowerBound * rowBytes..<start + range.upperBound * rowBytes)
    }

    // MARK: Matching

    /// How far the content moved from `before` to `after`, in rows (positive when it moved up, as scrolling down does),
    /// or `nil` when no shift lines them up. The smallest shift that does wins, since scrolling is smooth.
    static func shift(from before: [UInt64], to after: [UInt64]) -> Int? {
        let n = before.count
        let minOverlap = max(4, n / minOverlapShare)
        guard n > minOverlap else {
            return nil
        }
        for distance in 1...(n - minOverlap) {
            for shift in [distance, -distance] where matches(before, after, shift: shift) {
                return shift
            }
        }
        return nil
    }

    private static func matches(_ before: [UInt64], _ after: [UInt64], shift: Int) -> Bool {
        let overlap = before.count - abs(shift)
        let allowed = Int(Double(overlap) * tolerance)
        var misses = 0
        var distinct = Set<UInt64>()
        for i in 0..<overlap {
            // `shift` rows moved up: row `i + shift` before is row `i` after.
            let a = shift > 0 ? before[i + shift] : before[i]
            let b = shift > 0 ? after[i] : after[i - shift]
            if a != b {
                misses += 1
                if misses > allowed {
                    return false
                }
            }
            if distinct.count < 2 {
                distinct.insert(a)
            }
        }
        // A plain-coloured overlap fits every shift, so it says nothing.
        return distinct.count >= 2
    }

    /// The smallest share of mismatching rows over every shift, to tell a frame that changed in place from one that
    /// scrolled out of reach.
    private static func nearestMismatch(_ before: [UInt64], _ after: [UInt64]) -> Double {
        let n = before.count
        let minOverlap = max(4, n / minOverlapShare)
        guard n > minOverlap else {
            return 1
        }
        var best = 1.0
        for shift in -(n - minOverlap)...(n - minOverlap) {
            let overlap = n - abs(shift)
            var misses = 0
            for i in 0..<overlap {
                let a = shift > 0 ? before[i + shift] : before[i]
                let b = shift > 0 ? after[i] : after[i - shift]
                if a != b {
                    misses += 1
                }
            }
            best = min(best, Double(misses) / Double(overlap))
        }
        return best
    }

    /// One FNV-1a hash per row, so rows compare as numbers.
    static func rowHashes(_ bitmap: Bitmap) -> [UInt64] {
        let rowBytes = bitmap.bytesPerRow
        return bitmap.pixels.withUnsafeBytes { bytes in
            (0..<bitmap.height).map { y in
                var hash: UInt64 = 0xcbf29ce484222325
                for byte in bytes[y * rowBytes..<(y + 1) * rowBytes] {
                    hash = (hash ^ UInt64(byte)) &* 0x100000001b3
                }
                return hash
            }
        }
    }
}

extension Bitmap {
    /// The bitmap with rows and columns swapped, so the pixel at (x, y) moves to (y, x).
    public func transposed() -> Bitmap {
        var out = Data(count: pixels.count)
        pixels.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                for y in 0..<height {
                    for x in 0..<width {
                        let from = (y * width + x) * 4
                        let to = (x * height + y) * 4
                        dst[to] = src[from]
                        dst[to + 1] = src[from + 1]
                        dst[to + 2] = src[from + 2]
                        dst[to + 3] = src[from + 3]
                    }
                }
            }
        }
        return Bitmap(width: height, height: width, scale: scale, pixels: out)!
    }
}
