import Foundation

/// A frame of the scrolling area as 32-bit pixels, so rows and pixels compare as numbers.
struct ScrollFrame: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt32]

    init(_ bitmap: Bitmap) {
        width = bitmap.width
        height = bitmap.height
        let count = bitmap.width * bitmap.height
        pixels = [UInt32](unsafeUninitializedCapacity: count) { buffer, initialised in
            bitmap.pixels.copyBytes(to: UnsafeMutableRawBufferPointer(buffer))
            initialised = count
        }
    }
}

/// How far the content of a scrolling area moved between two frames, in both directions at once.
///
/// Textured patches of the earlier frame are searched for in the later one on a shrunken copy. Each patch that finds a
/// single clear match votes for how far it moved, and the largest group of agreeing votes wins, so something that stays
/// put (a sticky header, a floating button) can't pull the answer to zero. The winner is then pinned down to the pixel
/// on the full-size frames.
enum ScrollMotion {
    enum Result: Equatable {
        /// The content moved this far: pixel (x, y) of the later frame was pixel (x + dx, y + dy) of the earlier one, so
        /// scrolling down gives a positive `dy` and scrolling right a positive `dx`.
        case shift(dx: Int, dy: Int)
        /// Nothing scrolled.
        case still
        /// Too little to follow, or the same thing repeating, so no single shift fits.
        case featureless
        /// The patches don't agree, or found nothing: the content moved out of reach, or changed in place.
        case lost
    }

    /// A frame shrunk by `factor` in each direction, as brightness.
    struct Luma: Sendable {
        let width: Int
        let height: Int
        let factor: Int
        let values: [Int32]
    }

    private struct Offset: Hashable {
        var dx: Int
        var dy: Int
    }

    /// Patches searched for, at most. More cost time and bring little once the votes agree.
    private static let patchCount = 36
    /// The frame is cut into this many cells across and down, and each gives its most textured patch, so something that
    /// stays put and is busy, such as a sticky column, can't take every patch.
    private static let cells = 6
    /// Votes a shift needs, so one patch can't decide alone.
    private static let minimumVotes = 2
    /// Shifts tried on the real pixels, best supported first.
    private static let shiftsToTry = 24
    /// The share of the pixels that changed which the shift must explain.
    private static let minimumQuality = 0.8

    static func luma(of frame: ScrollFrame) -> Luma {
        let factor = min(frame.width, frame.height) >= 240 ? 4 : 1
        let width = frame.width / factor, height = frame.height / factor
        var values = [Int32](repeating: 0, count: width * height)
        frame.pixels.withUnsafeBufferPointer { pixels in
            for y in 0..<height {
                for x in 0..<width {
                    var sum: Int32 = 0
                    for j in 0..<factor {
                        let row = (y * factor + j) * frame.width + x * factor
                        for i in 0..<factor {
                            let v = pixels[row + i]
                            sum += Int32((v & 0xff) * 77 + ((v >> 8) & 0xff) * 151 + ((v >> 16) & 0xff) * 28) >> 8
                        }
                    }
                    values[y * width + x] = sum / Int32(factor * factor)
                }
            }
        }
        return Luma(width: width, height: height, factor: factor, values: values)
    }

    static func estimate(from previous: ScrollFrame, _ previousLuma: Luma, to current: ScrollFrame, _ currentLuma: Luma) -> Result {
        let factor = previousLuma.factor
        let patch = factor == 1 ? 8 : 12
        let radius = factor == 1 ? min(24, min(previousLuma.width, previousLuma.height) / 3) : 64
        guard previousLuma.width >= patch * 2, previousLuma.height >= patch * 2, radius > 0 else {
            return .featureless
        }
        let patches = texturedPatches(in: previousLuma, size: patch)
        guard patches.count >= 2 else {
            return .featureless
        }
        // Each patch votes for every place it fits about as well as the best, since something that repeats, such as a
        // label in every column, fits in several. The shift most patches agree on is the real one.
        var votes: [Offset: Int] = [:]
        for origin in patches {
            for offset in candidates(for: origin, size: patch, radius: radius, in: previousLuma, against: currentLuma) {
                votes[offset, default: 0] += 1
            }
        }
        if votes.isEmpty {
            return .lost
        }
        func support(_ offset: Offset) -> Int {
            votes.filter { abs($0.key.dx - offset.dx) <= 1 && abs($0.key.dy - offset.dy) <= 1 }.values.reduce(0, +)
        }
        // Any shift a patch voted for may be the real one, so the best supported are tried on the real pixels below; what
        // lines up exactly is the judge, not the vote count.
        let ranked = votes.keys.filter { $0.dx != 0 || $0.dy != 0 }.map { ($0, support($0)) }.sorted { $0.1 > $1.1 }
        let stays = support(Offset(dx: 0, dy: 0)) >= minimumVotes
        guard !ranked.isEmpty else {
            return stays ? .still : .lost
        }
        // The shrunken patches can't tell shifts apart that differ in the fine detail, so the best supported are tried
        // on the real pixels, where only the true one lines up. Two that line up equally well mean the content repeats
        // and the real shift can't be told.
        guard let changed = changedSamples(from: previous, to: current) else {
            return .featureless
        }
        var distinct: [Offset] = []
        var fits: [(offset: Offset, quality: Double)] = []
        for (offset, _) in ranked where distinct.count < shiftsToTry && !distinct.contains(where: { abs($0.dx - offset.dx) <= 2 && abs($0.dy - offset.dy) <= 2 }) {
            distinct.append(offset)
            if let fit = refine(Offset(dx: offset.dx * factor, dy: offset.dy * factor), range: factor, samples: changed, in: previous) {
                fits.append(fit)
            }
        }
        guard let best = fits.max(by: { $0.quality < $1.quality }) else {
            return stays ? .still : .lost
        }
        if fits.contains(where: { $0.offset != best.offset && $0.quality >= best.quality - 0.05 }) {
            return .featureless
        }
        return .shift(dx: best.offset.dx, dy: best.offset.dy)
    }

    // MARK: Patches

    /// Top-left corners of the patches of `luma` with the most going on in them, the best of each part of the frame.
    private static func texturedPatches(in luma: Luma, size: Int) -> [(x: Int, y: Int)] {
        var best: [Int: (x: Int, y: Int, score: Int)] = [:]
        for y in stride(from: 0, through: luma.height - size, by: size) {
            for x in stride(from: 0, through: luma.width - size, by: size) {
                var sum = 0, squares = 0
                for j in 0..<size {
                    for i in 0..<size {
                        let v = Int(luma.values[(y + j) * luma.width + x + i])
                        sum += v
                        squares += v * v
                    }
                }
                let count = size * size
                let variance = squares - sum * sum / count
                // Flat areas say nothing, and neither does a faint texture.
                let cell = (y * cells / luma.height) * cells + x * cells / luma.width
                if variance > count * 150, variance > (best[cell]?.score ?? 0) {
                    best[cell] = (x, y, variance)
                }
            }
        }
        return best.values.sorted { $0.score > $1.score }.prefix(patchCount).map { ($0.x, $0.y) }
    }

    /// Where `patch` of `previous` may have gone in `current`: every place within `radius` that fits nearly as well as
    /// the best one, as offsets the content may have moved by. None when it fits nowhere.
    private static func candidates(for patch: (x: Int, y: Int), size: Int, radius: Int, in previous: Luma, against current: Luma) -> [Offset] {
        let area = size * size
        let x0 = max(0, patch.x - radius), x1 = min(current.width - size, patch.x + radius)
        let y0 = max(0, patch.y - radius), y1 = min(current.height - size, patch.y + radius)
        guard x0 <= x1, y0 <= y1 else {
            return []
        }
        let columns = x1 - x0 + 1
        var sums = [Int](repeating: Int.max, count: columns * (y1 - y0 + 1))
        var best = Int.max
        previous.values.withUnsafeBufferPointer { a in
            current.values.withUnsafeBufferPointer { b in
                for qy in y0...y1 {
                    for qx in x0...x1 {
                        // Anything much worse than the best so far can't count as a rival.
                        let bound = best == Int.max ? Int.max : best * 2 + area * 30
                        var sum = 0
                        rows: for j in 0..<size {
                            let pa = (patch.y + j) * previous.width + patch.x
                            let pb = (qy + j) * current.width + qx
                            for i in 0..<size {
                                let d = Int(a[pa + i] - b[pb + i])
                                sum += d * d
                            }
                            if sum > bound {
                                break rows
                            }
                        }
                        if sum <= bound {
                            sums[(qy - y0) * columns + qx - x0] = sum
                            best = min(best, sum)
                        }
                    }
                }
            }
        }
        // A fair fit is needed to count at all.
        guard best <= area * 400 else {
            return []
        }
        let limit = best * 2 + area * 30
        var fits = sums.indices.filter { sums[$0] <= limit }.sorted { sums[$0] < sums[$1] }
        var found: [Offset] = []
        while let index = fits.first, found.count < 8 {
            let qx = x0 + index % columns, qy = y0 + index / columns
            found.append(Offset(dx: patch.x - qx, dy: patch.y - qy))
            // Places next to one already taken are the same fit.
            fits.removeAll { abs(x0 + $0 % columns - qx) <= 2 && abs(y0 + $0 / columns - qy) <= 2 }
        }
        return found
    }

    // MARK: Refining

    private typealias Sample = (x: Int, y: Int, value: UInt32)

    /// Pixels, sampled across the frame, that differ between the frames; nil when too few do to say anything.
    private static func changedSamples(from previous: ScrollFrame, to current: ScrollFrame) -> [Sample]? {
        let (w, h) = (current.width, current.height)
        let stepX = max(1, w / 160), stepY = max(1, h / 220)
        var changed: [Sample] = []
        for y in stride(from: 0, to: h, by: stepY) {
            for x in stride(from: 0, to: w, by: stepX) where previous.pixels[y * w + x] != current.pixels[y * w + x] {
                changed.append((x, y, current.pixels[y * w + x]))
            }
        }
        return changed.count >= 20 ? changed : nil
    }

    /// The shift within `range` pixels of `guess` that explains the most of `samples`, and the share it explains of those
    /// that have a counterpart in the earlier frame. Nil when that share is too small.
    private static func refine(_ guess: Offset, range: Int, samples: [Sample], in previous: ScrollFrame) -> (offset: Offset, quality: Double)? {
        let (w, h) = (previous.width, previous.height)
        var best = -1, bestOffset = guess, bestComparable = 0
        for dy in guess.dy - range...guess.dy + range {
            for dx in guess.dx - range...guess.dx + range {
                var score = 0, comparable = 0
                for sample in samples {
                    let xs = sample.x + dx, ys = sample.y + dy
                    // A pixel that came from outside the earlier frame has nothing to be compared with.
                    guard xs >= 0, xs < w, ys >= 0, ys < h else {
                        continue
                    }
                    comparable += 1
                    if previous.pixels[ys * w + xs] == sample.value {
                        score += 1
                    }
                }
                if score > best {
                    best = score
                    bestOffset = Offset(dx: dx, dy: dy)
                    bestComparable = comparable
                }
            }
        }
        guard bestComparable >= 20, Double(best) / Double(bestComparable) >= minimumQuality else {
            return nil
        }
        return (bestOffset, Double(best) / Double(bestComparable))
    }
}
