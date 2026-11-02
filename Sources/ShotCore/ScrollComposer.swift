import CoreGraphics
import Foundation

/// A frame kept for the final pass: where the area was in the image's coordinates, and what it showed, tightly packed
/// in the frames' byte order.
struct ScrollKeyFrame: Sendable {
    let x: Int
    let y: Int
    let pixels: [UInt8]
}

/// The rows and columns of the area that stay where they are while the content moves: a bar along the top or bottom
/// (rows that stay put in y), a column along the left or right (columns that stay put in x). Counts from each edge.
struct ScrollBands: Equatable, Sendable {
    var top = 0
    var bottom = 0
    var left = 0
    var right = 0
}

/// A pinned part that isn't a band across the whole area, such as a floating button or a banner in a corner: where it
/// is in the frame, and the corner of the image it stays with.
struct ScrollBlob: Equatable, Sendable {
    var x0: Int
    var y0: Int
    var x1: Int
    var y1: Int
    var left: Bool
    var top: Bool
}

/// Votes on which rows and columns of the area stay put while the content moves, gathered pair by pair as the frames
/// come. A pixel with detail votes in an axis once two frames moved enough along it to tell: that it stayed where it
/// was, or that it followed the content. Pairs a few tens of pixels apart are what make this work: a bar taller than
/// the move still has its own pixels to compare, which it wouldn't against a frame a whole screen away.
struct ScrollBandVotes: Sendable {
    private var votesY: [Int32]
    private var stayY: [Int32]
    private var votesX: [Int32]
    private var stayX: [Int32]
    /// The same votes at each pixel on the grid the votes are taken on, to find pinned parts that aren't bands.
    private var mapVotes: [Int32]
    private var mapStays: [Int32]
    private let width: Int
    private let height: Int
    private static let step = 2

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        votesY = [Int32](repeating: 0, count: height)
        stayY = votesY
        votesX = [Int32](repeating: 0, count: width)
        stayX = votesX
        mapVotes = [Int32](repeating: 0, count: (width / Self.step) * (height / Self.step))
        mapStays = mapVotes
    }

    @_optimize(speed)
    @inline(__always)
    private static func residual(_ a: UnsafePointer<UInt8>, _ b: UnsafePointer<UInt8>, _ width: Int, _ height: Int, _ ia: Int, _ ub: Int, _ vb: Int) -> Int32 {
        guard ub >= 0, ub < width, vb >= 0, vb < height else {
            return 255
        }
        let ib = (vb * width + ub) * 4
        return Int32(abs(Int(a[ia]) - Int(b[ib])) + abs(Int(a[ia + 1]) - Int(b[ib + 1])) + abs(Int(a[ia + 2]) - Int(b[ib + 2]))) / 3
    }

    /// The same test from the second frame's side: its pixel here against the first frame a move on. A pixel that
    /// seems to have stayed only because where it would have gone is hidden, as just beside a pinned column, looks
    /// just as much like it followed from this side; one that is pinned doesn't.
    @_optimize(speed)
    @inline(__always)
    private static func reverse(_ a: UnsafePointer<UInt8>, _ b: UnsafePointer<UInt8>, _ width: Int, _ height: Int, _ ib: Int, _ ua: Int, _ va: Int) -> Int32 {
        guard ua >= 0, ua < width, va >= 0, va < height else {
            return 255
        }
        let ia = (va * width + ua) * 4
        return Int32(abs(Int(b[ib]) - Int(a[ia])) + abs(Int(b[ib + 1]) - Int(a[ia + 1])) + abs(Int(b[ib + 2]) - Int(a[ia + 2]))) / 3
    }

    /// Takes the pair `a`, `b`, where `b` is the area `shift` pixels on from `a`.
    @_optimize(speed)
    /// The `edge` columns at the right are where an overlay scroll bar's thumb sits; it moves a pixel for a screenful, so
    /// it looks pinned, and a few of its votes in the rows below a bar chain across the blank rows there into the bar.
    /// They don't vote on rows.
    mutating func add(from a: UnsafePointer<UInt8>, to b: UnsafePointer<UInt8>, shift: (x: Int, y: Int), scale: Int, edge: Int = 0) {
        let step = 2
        let minimumMove = max(12, 6 * scale)
        let useY = abs(shift.y) >= minimumMove, useX = abs(shift.x) >= minimumMove
        guard useY || useX else {
            return
        }
        let width = width, height = height
        for v in stride(from: 0, to: height - step, by: step) {
            for u in stride(from: 0, to: width - step, by: step) {
                let ia = (v * width + u) * 4
                // Only pixels with detail can say anything.
                let right = ia + step * 4, below = ia + step * width * 4
                let detail = abs(Int(a[ia]) - Int(a[right])) + abs(Int(a[ia + 1]) - Int(a[right + 1])) + abs(Int(a[ia + 2]) - Int(a[right + 2])) + abs(Int(a[ia]) - Int(a[below])) + abs(Int(a[ia + 1]) - Int(a[below + 1])) + abs(Int(a[ia + 2]) - Int(a[below + 2]))
                guard detail >= 36 else {
                    continue
                }
                let stay = Self.residual(a, b, width, height, ia, u, v), follow = Self.residual(a, b, width, height, ia, u - shift.x, v - shift.y)
                let stayOnlyY = Self.residual(a, b, width, height, ia, u - shift.x, v), stayOnlyX = Self.residual(a, b, width, height, ia, u, v - shift.y)
                let cell = (v / step) * (width / step) + u / step
                let ib = ia
                if useY {
                    let back = min(Self.reverse(a, b, width, height, ib, u + shift.x, v + shift.y), Self.reverse(a, b, width, height, ib, u, v + shift.y))
                    if u < width - edge {
                        Self.vote(stay: min(stay, stayOnlyY), follow: min(follow, stayOnlyX), back: back, votes: &votesY[v], stays: &stayY[v])
                    }
                    Self.vote(stay: min(stay, stayOnlyY), follow: min(follow, stayOnlyX), back: back, votes: &mapVotes[cell], stays: &mapStays[cell], untested: true)
                }
                if useX {
                    let back = min(Self.reverse(a, b, width, height, ib, u + shift.x, v + shift.y), Self.reverse(a, b, width, height, ib, u + shift.x, v))
                    Self.vote(stay: min(stay, stayOnlyX), follow: min(follow, stayOnlyY), back: back, votes: &votesX[u], stays: &stayX[u])
                    Self.vote(stay: min(stay, stayOnlyX), follow: min(follow, stayOnlyY), back: back, votes: &mapVotes[cell], stays: &mapStays[cell], untested: true)
                }
            }
        }
    }

    /// The pinned parts outside the bands: pixels that stayed in nearly every vote, joined into parts when they're close
    /// together, each boxed. A part stays with the corner of the image it's nearest.
    @_optimize(speed)
    func blobs(bands: ScrollBands, scale: Int) -> [ScrollBlob] {
        let step = Self.step
        let columns = width / step, rows = height / step
        var pinned = [Bool](repeating: false, count: columns * rows)
        for r in 0..<rows {
            let v = r * step
            guard v >= bands.top, v < height - bands.bottom else {
                continue
            }
            for c in 0..<columns {
                let u = c * step
                guard u >= bands.left, u < width - bands.right else {
                    continue
                }
                let i = r * columns + c
                pinned[i] = mapStays[i] >= 3 && Float(mapStays[i]) >= 0.9 * Float(mapVotes[i])
            }
        }
        // Pixels of one part are a few away from each other, so each is spread by this much before they're joined.
        let reach = max(2, 6 * scale / step)
        var spread = [Bool](repeating: false, count: pinned.count)
        for r in 0..<rows {
            for c in 0..<columns where pinned[r * columns + c] {
                for rr in max(0, r - reach)...min(rows - 1, r + reach) {
                    for cc in max(0, c - reach)...min(columns - 1, c + reach) {
                        spread[rr * columns + cc] = true
                    }
                }
            }
        }
        var label = [Int](repeating: -1, count: pinned.count)
        var blobs: [ScrollBlob] = []
        for start in 0..<pinned.count where spread[start] && label[start] < 0 {
            var stack = [start]
            label[start] = blobs.count
            var minC = columns, maxC = 0, minR = rows, maxR = 0, members = 0
            while let i = stack.popLast() {
                let r = i / columns, c = i % columns
                if pinned[i] {
                    members += 1
                    minC = min(minC, c); maxC = max(maxC, c); minR = min(minR, r); maxR = max(maxR, r)
                }
                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let rr = r + dr, cc = c + dc
                    if rr >= 0, rr < rows, cc >= 0, cc < columns, spread[rr * columns + cc], label[rr * columns + cc] < 0 {
                        label[rr * columns + cc] = blobs.count
                        stack.append(rr * columns + cc)
                    }
                }
            }
            guard members >= 6, maxC >= minC else {
                continue
            }
            let margin = 3 * scale
            let x0 = max(0, minC * step - margin), x1 = min(width, (maxC + 1) * step + margin)
            let y0 = max(0, minR * step - margin), y1 = min(height, (maxR + 1) * step + margin)
            // Not a floating part if it takes up most of the area, which is content that happened to hold still.
            guard (x1 - x0) * (y1 - y0) * 5 < width * height * 2 else {
                continue
            }
            blobs.append(ScrollBlob(x0: x0, y0: y0, x1: x1, y1: y1, left: (x0 + x1) / 2 < width / 2, top: (y0 + y1) / 2 < height / 2))
        }
        return blobs
    }

    /// A pixel votes only when both ways could be tested: a pixel whose place after the move is off the frame can't
    /// say whether it followed the content, and it would vote that it stayed whenever it happened to look like what
    /// was there.
    ///
    /// When a move is as tall as the rows above it, as a page that jumps a whole step per frame, the pixels in those
    /// rows have no place to follow to. They can still vote that they stayed if the pixel in the later frame isn't what
    /// the content from that far on would have brought there: the same test from the other side. Only the map of pinned
    /// parts takes such votes (`untested`): a row's votes would otherwise be nothing but a pinned part's, and a list in
    /// a margin would make every row above it look like a bar.
    private static func vote(stay: Int32, follow: Int32, back: Int32, votes: inout Int32, stays: inout Int32, untested allowed: Bool = false) {
        let threshold: Int32 = 8, margin: Int32 = 10, far: Int32 = 255
        guard stay < far, follow < far || (allowed && back < far) else {
            return
        }
        // With nothing to follow to, the reverse test is the only evidence, so it has to be clear: text rasterised a
        // little differently in two frames can differ by this much less than a pixel that was replaced.
        let untested = follow >= far
        if stay < threshold, stay + margin < follow, back >= (untested ? 6 * threshold : threshold) {
            votes += 1
            stays += 1
        } else if follow < threshold, follow + margin < stay {
            votes += 1
        }
    }

    /// Which rows and columns are pinned: a row or column is when most of its votes stayed, and a band runs from the
    /// edge to its last pinned row, across the gaps a bar's own padding leaves.
    func bands(scale: Int) -> ScrollBands {
        let gap = 20 * scale
        // Rows where at least 60% of the width's sampled pixels stayed: a bar's rule, where a pinned column's is short.
        let cells = width / Self.step
        let wide = (0..<height).map { v -> Bool in
            let row = v / Self.step
            guard v % Self.step == 0, cells > 0, (row + 1) * cells <= mapStays.count else {
                return false
            }
            return (0..<cells).reduce(0) { $0 + (mapStays[row * cells + $1] > 0 ? 1 : 0) } * 5 >= cells * 3
        }
        // The same for columns: a pinned column's right edge is a rule that runs down most of the height, and the column
        // can be blank beside its labels, as a spreadsheet's first column is, for far more than a bar's padding.
        let rowCount = height / Self.step
        let tall = (0..<width).map { u -> Bool in
            let column = u / Self.step
            guard u % Self.step == 0, rowCount > 0, column < cells else {
                return false
            }
            return (0..<rowCount).reduce(0) { $0 + (mapStays[$1 * cells + column] > 0 ? 1 : 0) } * 5 >= rowCount * 3
        }
        return ScrollBands(
            top: Self.band(votes: votesY, stays: stayY, fromStart: true, gap: gap, wide: wide),
            bottom: Self.band(votes: votesY, stays: stayY, fromStart: false, gap: gap, wide: wide),
            left: Self.band(votes: votesX, stays: stayX, fromStart: true, gap: gap, wide: tall, farRule: true),
            right: Self.band(votes: votesX, stays: stayX, fromStart: false, gap: gap, wide: tall, farRule: true)
        )
    }

    /// How many rows or columns from an edge are pinned: up to the last one whose votes mostly stayed, as long as no
    /// more than `gap` unpinned ones come between, and no more than 45% of the area.
    private static func band(votes: [Int32], stays: [Int32], fromStart: Bool, gap: Int, wide: [Bool]? = nil, farRule: Bool = false) -> Int {
        let count = votes.count
        // A bar's own pixels give nearly every vote as stayed, over several rows; a stray row of content whose shapes
        // happen to repeat doesn't.
        let pinned = (0..<count).map { stays[$0] >= 4 && Float(stays[$0]) >= 0.9 * Float(votes[$0]) }
        func isPinned(_ k: Int) -> Bool {
            // Votes are on every other row, so a neighbour is within two.
            // A thin rule has one row and plenty of votes.
            pinned[k] && (stays[k] >= 200 || (k > 1 && (pinned[k - 1] || pinned[k - 2])) || (k + 2 < count && (pinned[k + 1] || pinned[k + 2])))
        }
        let limit = count * 45 / 100
        /// The next row at or after `i` (counted from the edge) that is a pinned rule across most of the width, within
        /// two gaps (or anywhere, for a column) and with no content between; nil otherwise. A rule that's only part of the width is a pinned
        /// column's cell border, not a bar's edge.
        func ruleAhead(from i: Int) -> Int? {
            guard let wide else {
                return nil
            }
            for j in i..<(farRule ? limit : min(i + 2 * gap, limit)) {
                let k = fromStart ? j : count - 1 - j
                if isPinned(k), stays[k] >= 200, wide[k] {
                    return j
                }
                if votes[k] >= 100, Float(stays[k]) < 0.75 * Float(votes[k]) {
                    return nil
                }
            }
            return nil
        }
        var last = -1
        var i = 0
        while i < limit {
            let k = fromStart ? i : count - 1 - i
            if isPinned(k) {
                last = i
            } else if votes[k] >= 100, Float(stays[k]) < 0.75 * Float(votes[k]) {
                // Content, which a bar's own padding, with nothing in it to vote, never is.
                if last >= 0 {
                    break
                }
            } else if i - last > (last < 0 ? 3 * gap : gap) {
                // A bar with deep padding is closed by a rule that stayed put, which content never does: a rule of
                // the page moves with it. The band reaches such a rule across the blank rows, but not across content.
                if last >= 0, let rule = ruleAhead(from: i) {
                    i = rule
                    continue
                }
                break
            }
            i += 1
        }
        return last + 1
    }
}

/// Builds the stitched image once the capture is over, from every frame that was kept rather than one at a time as
/// they came.
///
/// With all the frames to hand, two things that are guesses while capturing become measurements. What's pinned is
/// found from how every pair of frames agrees at each pixel, so a bar is known from its first frame to its last and
/// its edge to the pixel. And each pixel of the image is the one most of the frames that saw it agree on, so a scroll
/// bar that fades over an edge, a bounce, a cursor or a bar that was pinned for only part of the time is outvoted
/// instead of overwriting what was right.
enum ScrollComposer {
    /// Samples kept for each pixel of the image; more than this saw it and the rest are ignored.
    private static let samples = 10
    /// How alike two samples are to agree: the sum of their channels' differences.
    private static let agreeing = 30

    // MARK: Composing

    /// The image over `bounds`, in the frames' byte order with alpha 255 where something was seen and 0 where not.
    /// A pixel is what most of the frames that saw it agree on, preferring the one that saw it nearest their middle,
    /// where a bar or a shadow at an edge can't reach. Where only a pinned band saw it, the band's.
    @_optimize(speed)
    static func compose(keys: [ScrollKeyFrame], width: Int, height: Int, bounds: ScrollCanvas.Bounds, bands: ScrollBands, blobs: [ScrollBlob] = [], edge: Int = 0) -> [UInt8]? {
        let outWidth = bounds.width, outHeight = bounds.height
        guard outWidth > 0, outHeight > 0, !keys.isEmpty, keys.allSatisfy({ $0.pixels.count == width * height * 4 }) else {
            return nil
        }
        var out = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        let k = samples
        let stripe = max(8, min(128, 4_000_000 / (outWidth * k)))
        // Where a frame's row or column goes when it's pinned, and how near the middle of the frame it is.
        let rowBand = (0..<height).map { $0 < bands.top ? 1 : $0 >= height - bands.bottom ? 2 : 0 }
        let columnBand = (0..<width).map { $0 < bands.left ? 1 : $0 >= width - bands.right ? 2 : 0 }
        let columnWeight = (0..<width).map { UInt8(min(255, abs(2 * $0 - width) * 255 / width)) }
        let rowWeight = (0..<height).map { UInt8(min(255, abs(2 * $0 - height) * 255 / height)) }
        // Which part, if any, each pixel of a frame belongs to, as its index in `blobs` plus one.
        var blobAt = [UInt8](repeating: 0, count: width * height)
        for (index, blob) in blobs.prefix(250).enumerated() {
            for v in blob.y0..<blob.y1 {
                for u in blob.x0..<blob.x1 {
                    blobAt[v * width + u] = UInt8(index + 1)
                }
            }
        }
        func anchoredX(_ u: Int) -> Int { columnBand[u] == 1 ? u : outWidth - (width - u) }
        func anchoredY(_ v: Int) -> Int { rowBand[v] == 1 ? v : outHeight - (height - v) }

        // Raw buffers, since this runs over every pixel of every frame and arrays captured by closures are slow.
        let slots = stripe * outWidth * 2
        let colors = UnsafeMutablePointer<UInt32>.allocate(capacity: slots * k)
        let weights = UnsafeMutablePointer<UInt8>.allocate(capacity: slots * k)
        let counts = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
        // Output pixels a pinned part hid in some frame: if no frame showed one clean, it is a hole to fill.
        let hidden = UnsafeMutablePointer<UInt8>.allocate(capacity: stripe * outWidth)
        colors.initialize(repeating: 0, count: slots * k)
        weights.initialize(repeating: 0, count: slots * k)
        counts.initialize(repeating: 0, count: slots)
        defer {
            colors.deallocate()
            weights.deallocate()
            counts.deallocate()
            hidden.deallocate()
        }
        var y0 = 0
        while y0 < outHeight {
            let y1 = min(outHeight, y0 + stripe)
            counts.update(repeating: 0, count: slots)
            hidden.update(repeating: 0, count: stripe * outWidth)
            let layer = stripe * outWidth
            for key in keys {
                key.pixels.withUnsafeBufferPointer { frame in
                    frame.baseAddress!.withMemoryRebound(to: UInt32.self, capacity: width * height) { pixels in
                        @inline(__always) func add(_ wx: Int, _ wy: Int, _ u: Int, _ v: Int, pinned: Bool) {
                            guard wx >= 0, wx < outWidth, wy >= y0, wy < y1 else {
                                return
                            }
                            let slot = (wy - y0) * outWidth + wx + (pinned ? layer : 0)
                            let n = Int(counts[slot])
                            guard n < k else {
                                return
                            }
                            colors[slot * k + n] = pixels[v * width + u]
                            weights[slot * k + n] = max(columnWeight[u], rowWeight[v])
                            counts[slot] = UInt8(n + 1)
                        }
                        for v in 0..<height {
                            if rowBand[v] == 0 {
                                let wy = key.y - bounds.y0 + v
                                guard wy >= y0, wy < y1 else {
                                    continue
                                }
                                for u in 0..<width {
                                    if columnBand[u] == 0 {
                                        let part = Int(blobAt[v * width + u])
                                        if part == 0 {
                                            add(key.x - bounds.x0 + u, wy, u, v, pinned: false)
                                        } else {
                                            let blob = blobs[part - 1]
                                            let wx = key.x - bounds.x0 + u
                                            if wx >= 0, wx < outWidth {
                                                hidden[(wy - y0) * outWidth + wx] = 1
                                            }
                                            add(blob.left ? u : outWidth - (width - u), blob.top ? v : outHeight - (height - v), u, v, pinned: true)
                                        }
                                    } else {
                                        add(anchoredX(u), wy, u, v, pinned: true)
                                    }
                                }
                            } else {
                                let wy = anchoredY(v)
                                guard wy >= y0, wy < y1 else {
                                    continue
                                }
                                for u in 0..<width {
                                    add(columnBand[u] == 0 ? key.x - bounds.x0 + u : anchoredX(u), wy, u, v, pinned: true)
                                }
                            }
                        }
                    }
                }
            }
            // The middle of each row first, then its edges: where the samples at an edge disagree, a scroll bar that
            // fades in there may have been over the pixel for most of the frames that saw it, so the sample nearest the
            // pixel just inside the strip is taken, which the bar never covers.
            let inner = min(outWidth / 2, max(edge, 1))
            for wy in y0..<y1 {
                for pass in 0..<2 {
                    for wx in 0..<outWidth {
                        let atEdge = edge > 0 && (wx < inner || wx >= outWidth - inner)
                        guard atEdge == (pass == 1) else {
                            continue
                        }
                        let slot = (wy - y0) * outWidth + wx
                        let content = Int(counts[slot]), pinned = Int(counts[slot + layer])
                        guard content > 0 || pinned > 0 else {
                            continue
                        }
                        let base = content > 0 ? slot : slot + layer
                        var reference: UInt32?
                        var closer: UInt32?
                        if atEdge, content > 1 {
                            let rx = wx < inner ? inner : outWidth - inner - 1
                            let ro = (wy * outWidth + rx) * 4
                            if out[ro + 3] == 255 {
                                reference = UInt32(out[ro]) | UInt32(out[ro + 1]) << 8 | UInt32(out[ro + 2]) << 16
                            }
                            // Content can reach into the strip (a chat bubble that ends inside it), so the pixel at the
                            // strip's inner side is no help in that row. One nearer the edge, still clear of a bar's
                            // thumb, is the page there.
                            let nx = wx < inner ? edge * 2 / 3 : outWidth - edge * 2 / 3 - 1
                            if nx >= 0, nx < outWidth, nx != rx {
                                let no = (wy * outWidth + nx) * 4
                                if out[no + 3] == 255 {
                                    closer = UInt32(out[no]) | UInt32(out[no + 1]) << 8 | UInt32(out[no + 2]) << 16
                                }
                            }
                        }
                        let color = consensus(colors, weights, base * k, content > 0 ? content : pinned, near: reference, alsoNear: closer)
                        let o = (wy * outWidth + wx) * 4
                        out[o] = UInt8(truncatingIfNeeded: color)
                        out[o + 1] = UInt8(truncatingIfNeeded: color >> 8)
                        out[o + 2] = UInt8(truncatingIfNeeded: color >> 16)
                        out[o + 3] = 255
                    }
                }
            }
            // A part that sits at the same place in every frame, over rows that repeat at the move's period, hides
            // the same rows each time (a list's lines under a step of a whole number of them), and nothing shows what
            // is under them. Each such run takes its neighbours' colour, the nearer one for each pixel.
            for wy in y0..<y1 {
                let row = (wy - y0) * outWidth
                var wx = 0
                while wx < outWidth {
                    guard hidden[row + wx] != 0, out[(wy * outWidth + wx) * 4 + 3] == 0 else {
                        wx += 1
                        continue
                    }
                    var end = wx
                    while end < outWidth, hidden[row + end] != 0, out[(wy * outWidth + end) * 4 + 3] == 0 {
                        end += 1
                    }
                    let left = wx > 0 ? (wy * outWidth + wx - 1) * 4 : -1, right = end < outWidth ? (wy * outWidth + end) * 4 : -1
                    for x in wx..<end {
                        let from = left >= 0 && (right < 0 || x - wx < end - x) ? left : right
                        guard from >= 0, out[from + 3] == 255 else {
                            continue
                        }
                        let o = (wy * outWidth + x) * 4
                        out[o] = out[from]
                        out[o + 1] = out[from + 1]
                        out[o + 2] = out[from + 2]
                        out[o + 3] = 255
                    }
                    wx = end
                }
            }
            y0 = y1
        }
        return out
    }

    @_optimize(speed)
    @inline(__always) private static func close(_ a: UInt32, _ b: UInt32) -> Bool {
        let d0 = abs(Int(a & 255) - Int(b & 255)), d1 = abs(Int((a >> 8) & 255) - Int((b >> 8) & 255)), d2 = abs(Int((a >> 16) & 255) - Int((b >> 16) & 255))
        return d0 + d1 + d2 <= agreeing
    }

    /// The sample most of the others agree with; of equals, the one seen nearest the middle of its frame. With a
    /// `near` colour, the sample closest to it if one is close and the samples disagree.
    @_optimize(speed)
    private static func consensus(_ colors: UnsafeMutablePointer<UInt32>, _ weights: UnsafeMutablePointer<UInt8>, _ start: Int, _ n: Int, near: UInt32? = nil, alsoNear: UInt32? = nil) -> UInt32 {
        if n == 1 {
            return colors[start]
        }
        if let near {
            var allAgree = true
            for i in 1..<n where !close(colors[start], colors[start + i]) {
                allAgree = false
                break
            }
            if !allAgree {
                var closest = 0, least = Int.max
                for reference in [near, alsoNear].compactMap({ $0 }) {
                    for i in 0..<n {
                        let c = colors[start + i]
                        let d = abs(Int(c & 255) - Int(reference & 255)) + abs(Int((c >> 8) & 255) - Int((reference >> 8) & 255)) + abs(Int((c >> 16) & 255) - Int((reference >> 16) & 255))
                        if d < least {
                            least = d
                            closest = i
                        }
                    }
                }
                if least <= 3 * agreeing {
                    return colors[start + closest]
                }
            }
        }
        var best = 0, bestAgree = -1, bestWeight = 256
        for i in 0..<n {
            var agree = 0
            for j in 0..<n where close(colors[start + i], colors[start + j]) {
                agree += 1
            }
            let weight = Int(weights[start + i])
            if agree > bestAgree || (agree == bestAgree && weight < bestWeight) {
                best = i
                bestAgree = agree
                bestWeight = weight
            }
        }
        return colors[start + best]
    }

    /// Whether the seen pixels of `rect` in the composed image `pixels`, which covers `bounds`, are one flat colour.
    static func isBlank(_ pixels: [UInt8], bounds: ScrollCanvas.Bounds, rect: ScrollCanvas.Bounds) -> Bool {
        let area = rect.intersection(bounds)
        guard !area.isEmpty else {
            return false
        }
        var reference: (Int, Int, Int)?
        var counted = 0, differing = 0
        var wy = area.y0
        while wy < area.y1 {
            var wx = area.x0
            while wx < area.x1 {
                let i = ((wy - bounds.y0) * bounds.width + wx - bounds.x0) * 4
                if pixels[i + 3] == 255 {
                    let color = (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
                    if let reference {
                        counted += 1
                        if abs(color.0 - reference.0) + abs(color.1 - reference.1) + abs(color.2 - reference.2) > 24 {
                            differing += 1
                        }
                    } else {
                        reference = color
                    }
                }
                wx += 3
            }
            wy += 2
        }
        return counted >= 20 && differing * 50 <= counted
    }

    /// Whether the pixels of `frame` in the box are one flat colour.
    @_optimize(speed)
    static func isFlat(_ frame: [UInt8], width: Int, height: Int, x0: Int, y0: Int, x1: Int, y1: Int) -> Bool {
        let x0 = max(0, x0), y0 = max(0, y0), x1 = min(width, x1), y1 = min(height, y1)
        guard x1 > x0, y1 > y0, frame.count == width * height * 4 else {
            return false
        }
        let reference = (Int(frame[(y0 * width + x0) * 4]), Int(frame[(y0 * width + x0) * 4 + 1]), Int(frame[(y0 * width + x0) * 4 + 2]))
        var counted = 0, differing = 0
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let i = (y * width + x) * 4
                counted += 1
                if abs(Int(frame[i]) - reference.0) + abs(Int(frame[i + 1]) - reference.1) + abs(Int(frame[i + 2]) - reference.2) > 24 {
                    differing += 1
                }
                x += 3
            }
            y += 2
        }
        return counted >= 20 && differing * 50 <= counted
    }
}
