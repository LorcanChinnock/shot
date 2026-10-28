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

        /// This, shrunk by a further `times`, which costs a fraction of shrinking the frame again.
        func reduced(by times: Int) -> Luma {
            let (newWidth, newHeight) = (width / times, height / times)
            var reduced = [Int32](repeating: 0, count: newWidth * newHeight)
            for y in 0..<newHeight {
                for x in 0..<newWidth {
                    var sum: Int32 = 0
                    for j in 0..<times {
                        for i in 0..<times {
                            sum += values[(y * times + j) * width + x * times + i]
                        }
                    }
                    reduced[y * newWidth + x] = sum / Int32(times * times)
                }
            }
            return Luma(width: newWidth, height: newHeight, factor: factor * times, values: reduced)
        }
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
    private static let shiftsToTry = 12
    /// The share of the pixels that changed which the shift must explain.
    private static let minimumQuality = 0.5

    /// Whether two pixels are close enough to be the same thing drawn twice. A scroll that lands between two device
    /// pixels, as a trackpad's does, draws the same text a little differently each time, so exact equality never holds.
    static func similar(_ a: UInt32, _ b: UInt32) -> Bool {
        if a == b {
            return true
        }
        return difference(a, b) <= 36
    }

    /// `factor` shrinks the frame by that much in each direction; the default suits the frame's size.
    static func luma(of frame: ScrollFrame, factor requested: Int? = nil) -> Luma {
        let factor = requested ?? (min(frame.width, frame.height) >= 240 ? 4 : 1)
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

    /// `hint` is where the content is expected to have moved to, from how it moved before: scrolling is smooth, so a small
    /// look around it usually finds the answer at a fraction of the cost of a look at everything.
    static func estimate(from previous: ScrollFrame, _ previousLuma: Luma, to current: ScrollFrame, _ currentLuma: Luma, hint: (dx: Int, dy: Int)? = nil) -> Result {
        guard previousLuma.factor > 1 else {
            return search(from: previous, previousLuma, to: current, currentLuma)
        }
        if let hint {
            let near = search(from: previous, previousLuma, to: current, currentLuma, around: Offset(dx: hint.dx, dy: hint.dy), radius: 10)
            if case .shift = near {
                return near
            }
        }
        // Everywhere else, from a look at a smaller picture where the frames are big, which reaches a thousand pixels for
        // little work. Frames may be that far apart, since the machine can't always keep up with the screen.
        let times = min(previousLuma.width, previousLuma.height) >= 200 ? 4 : (min(previousLuma.width, previousLuma.height) >= 120 ? 2 : 1)
        guard times > 1 else {
            return search(from: previous, previousLuma, to: current, currentLuma)
        }
        return search(from: previous, previousLuma.reduced(by: times), to: current, currentLuma.reduced(by: times), fullSize: (previous, current))
    }

    private static func search(from previousFrame: ScrollFrame, _ previousLuma: Luma, to currentFrame: ScrollFrame, _ currentLuma: Luma, around center: Offset = Offset(dx: 0, dy: 0), radius requested: Int? = nil, fullSize: (ScrollFrame, ScrollFrame)? = nil) -> Result {
        let (previous, current) = fullSize ?? (previousFrame, currentFrame)
        let factor = previousLuma.factor
        let patch = factor == 4 ? 12 : 8
        let radius = requested ?? (factor == 1 ? min(24, min(previousLuma.width, previousLuma.height) / 3) : 64)
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
            for offset in candidates(for: origin, size: patch, radius: radius, around: Offset(dx: center.dx / factor, dy: center.dy / factor), in: previousLuma, against: currentLuma) {
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
        // lines up there is the judge, not the vote count.
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
        var local: [(offset: Offset, quality: Double)] = []
        // Not having moved, or having moved by a pixel or two, is tried first: scrolling slowly enough shows no shift in
        // the shrunken frames at all.
        for offset in [Offset(dx: 0, dy: 0)] + ranked.map(\.0) where distinct.count < shiftsToTry && !distinct.contains(where: { abs($0.dx - offset.dx) <= 2 && abs($0.dy - offset.dy) <= 2 }) {
            distinct.append(offset)
            guard let found = refine(Offset(dx: offset.dx * factor, dy: offset.dy * factor), range: factor, samples: changed, in: previous),
                  let quality = alignment(previous, current, shiftedBy: found.offset), quality >= 0.35
            else {
                continue
            }
            local.append((found.offset, quality))
        }
        // The best few are polished: the whole-pixel shift may be one off in either direction, which a fraction of a pixel
        // can't make up for.
        var fits: [(offset: Offset, quality: Double)] = []
        for (rank, candidate) in local.sorted(by: { $0.quality > $1.quality }).enumerated() {
            var (shifted, quality) = candidate
            if rank < 3 {
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let neighbour = Offset(dx: candidate.offset.dx + dx, dy: candidate.offset.dy + dy)
                        if let better = alignment(previous, current, shiftedBy: neighbour), better > quality {
                            quality = better
                            shifted = neighbour
                        }
                    }
                }
            }
            if quality >= minimumQuality {
                fits.append((shifted, quality))
            }
        }
        guard let best = fits.max(by: { $0.quality < $1.quality }) else {
            return stays ? .still : .lost
        }
        // Shifts a few pixels apart are the same answer found twice; only ones further apart make it ambiguous.
        if fits.contains(where: { max(abs($0.offset.dx - best.offset.dx), abs($0.offset.dy - best.offset.dy)) > 4 && $0.quality >= best.quality - 0.05 }) {
            return .featureless
        }
        if best.offset.dx == 0, best.offset.dy == 0 {
            return .still
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
    private static func candidates(for patch: (x: Int, y: Int), size: Int, radius: Int, around center: Offset, in previous: Luma, against current: Luma) -> [Offset] {
        let area = size * size
        // The patch is expected `center` away from where it was, in the direction the content moved.
        let expectedX = patch.x - center.dx, expectedY = patch.y - center.dy
        let x0 = max(0, expectedX - radius), x1 = min(current.width - size, expectedX + radius)
        let y0 = max(0, expectedY - radius), y1 = min(current.height - size, expectedY + radius)
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

    /// Pixels, sampled across the frame, that really differ between the frames, which a shift has to explain; at most a
    /// few thousand, since each candidate shift checks them all. Nil when too few differ to say anything.
    private static func changedSamples(from previous: ScrollFrame, to current: ScrollFrame) -> [Sample]? {
        let (w, h) = (current.width, current.height)
        let stepX = max(1, w / 120), stepY = max(1, h / 160)
        var changed: [Sample] = []
        for y in stride(from: 0, to: h, by: stepY) {
            for x in stride(from: 0, to: w, by: stepX) where !similar(previous.pixels[y * w + x], current.pixels[y * w + x]) {
                changed.append((x, y, current.pixels[y * w + x]))
            }
        }
        return changed.count >= 20 ? changed : nil
    }

    /// The shift within `range` pixels of `guess` that explains the most of `samples`, and the share it explains of those
    /// that have a counterpart in the earlier frame. Nil when that share is too small.
    private static func refine(_ guess: Offset, range: Int, samples: [Sample], in previous: ScrollFrame) -> (offset: Offset, quality: Double)? {
        // Coarsely over the whole range, then to the pixel around the best of that.
        let step = range > 4 ? 4 : 1
        var best = score(guess, samples: samples, in: previous, over: Array(stride(from: -range, through: range, by: step)))
        if step > 1, let coarse = best {
            best = score(coarse.offset, samples: samples, in: previous, over: Array(-(step - 1)...(step - 1)))
        }
        guard let found = best, found.quality >= 0.2 else {
            return nil
        }
        return found
    }

    /// The offset around `guess` by each of `deltas` in each direction that matches `samples` best, and how well.
    private static func score(_ guess: Offset, samples: [Sample], in previous: ScrollFrame, over deltas: [Int]) -> (offset: Offset, quality: Double)? {
        let (w, h) = (previous.width, previous.height)
        var best = -1.0, bestOffset = guess, bestComparable = 0
        for deltaY in deltas {
            for deltaX in deltas {
                let dx = guess.dx + deltaX, dy = guess.dy + deltaY
                var total = 0.0
                var comparable = 0
                for sample in samples {
                    let xs = sample.x + dx, ys = sample.y + dy
                    // A pixel that came from outside the earlier frame has nothing to be compared with.
                    guard xs >= 0, xs < w, ys >= 0, ys < h else {
                        continue
                    }
                    comparable += 1
                    // How close the pixels are, not only whether they are close enough: text drawn at a fraction of a pixel
                    // differs a little from itself, and something that merely resembles it differs a lot.
                    total += max(0, 1 - Double(difference(previous.pixels[ys * w + xs], sample.value)) / 150)
                }
                // Candidates compare by their average, since those near an edge have fewer pixels to compare.
                if comparable >= 20, bestComparable == 0 || total / Double(comparable) > best / Double(bestComparable) {
                    best = total
                    bestOffset = Offset(dx: dx, dy: dy)
                    bestComparable = comparable
                }
            }
        }
        return bestComparable >= 20 ? (bestOffset, best / Double(bestComparable)) : nil
    }

    /// How well `current`, moved back by `shift`, matches `previous`, from 0 to 1. Each dark mark in `current` (text, lines)
    /// is compared with the same place in `previous` shifted by a fraction of a pixel, since the true shift usually isn't a
    /// whole number of pixels and text drawn at a fraction of a pixel differs from itself at the edges. The same text
    /// fits at some fraction with almost no error. Different text in the same layout, such as a table whose numbers
    /// differ, doesn't fit at any, however much its lines and cells line up. The middle of the scores of tiles across
    /// the shared part is used, so a few matching tiles can't carry the rest. Nil when they share too little.
    private static func alignment(_ previous: ScrollFrame, _ current: ScrollFrame, shiftedBy shift: Offset) -> Double? {
        let (w, h) = (previous.width, previous.height)
        let tiles = 4
        struct Mark {
            var x: Int, y: Int, brightness: Int, tile: Int
        }
        var marks: [Mark] = []
        for y in stride(from: 0, to: h, by: 2) {
            let ys = y + shift.dy
            guard ys >= 1, ys < h - 1 else {
                continue
            }
            for x in stride(from: 0, to: w, by: 2) {
                let xs = x + shift.dx
                guard xs >= 1, xs < w - 1 else {
                    continue
                }
                let b = brightness(current.pixels[y * w + x])
                // Background says nothing: only what stands out is looked for.
                if b < 200 {
                    marks.append(Mark(x: xs, y: ys, brightness: b, tile: (y * tiles / h) * tiles + x * tiles / w))
                }
            }
        }
        guard marks.count >= 100 else {
            return nil
        }
        // A few thousand marks tell as much as all of them, at a fraction of the cost.
        if marks.count > 3000 {
            let step = marks.count / 3000 + 1
            marks = marks.enumerated().filter { $0.offset % step == 0 }.map(\.element)
        }
        // The brightness of `previous` at a fraction of a pixel from (x, y), by blending with the neighbour that way.
        func sample(_ x: Int, _ y: Int, _ fx: Double, _ fy: Double) -> Double {
            let nx = fx < 0 ? x - 1 : x + 1, ny = fy < 0 ? y - 1 : y + 1
            let ax = abs(fx), ay = abs(fy)
            let p00 = Double(brightness(previous.pixels[y * w + x])), p10 = Double(brightness(previous.pixels[y * w + nx]))
            let p01 = Double(brightness(previous.pixels[ny * w + x])), p11 = Double(brightness(previous.pixels[ny * w + nx]))
            return (p00 * (1 - ax) + p10 * ax) * (1 - ay) + (p01 * (1 - ax) + p11 * ax) * ay
        }
        let fractions: [Double] = [-0.5, -0.25, 0, 0.25, 0.5]
        var bestError = Double.infinity, bestFraction = (0.0, 0.0)
        for fy in fractions {
            for fx in fractions {
                var error = 0.0
                for mark in marks {
                    error += abs(Double(mark.brightness) - sample(mark.x, mark.y, fx, fy))
                }
                if error < bestError {
                    bestError = error
                    bestFraction = (fx, fy)
                }
            }
        }
        var errors = [Double](repeating: 0, count: tiles * tiles), counts = [Double](repeating: 0, count: tiles * tiles)
        for mark in marks {
            errors[mark.tile] += abs(Double(mark.brightness) - sample(mark.x, mark.y, bestFraction.0, bestFraction.1))
            counts[mark.tile] += 1
        }
        var scores: [Double] = []
        for tile in 0..<tiles * tiles where counts[tile] >= 15 {
            scores.append(max(0, 1 - errors[tile] / counts[tile] / 70))
        }
        guard scores.count >= 3 else {
            return nil
        }
        scores.sort()
        return scores[scores.count / 2]
    }

    private static func brightness(_ pixel: UInt32) -> Int {
        Int((pixel & 0xff) * 77 + ((pixel >> 8) & 0xff) * 151 + ((pixel >> 16) & 0xff) * 28) >> 8
    }

    /// The summed difference of the red, green and blue of two pixels.
    static func difference(_ a: UInt32, _ b: UInt32) -> Int {
        func gap(_ shift: UInt32) -> Int { abs(Int((a >> shift) & 0xff) - Int((b >> shift) & 0xff)) }
        return gap(0) + gap(8) + gap(16)
    }
}
