import CoreGraphics
import Foundation

/// One frame of the scrolling area as the screen shows it: 4 bytes a pixel with alpha last in memory (BGRA or RGBA),
/// top row first. The pointer is only read while `process` runs.
public struct ScrollFrame {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let pixels: UnsafeRawBufferPointer

    public init(width: Int, height: Int, bytesPerRow: Int, pixels: UnsafeRawBufferPointer) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }
}

/// Builds one image out of the frames of an area the person scrolls themselves, in any direction.
///
/// Each new frame is lined up with the last one: phase correlation on a small grey copy proposes the likely moves, and
/// each is checked tile by tile against the pixels, so a repeating table or a sticky header can't fool it. The frame
/// is then anchored to the canvas at device resolution, so every join is within a pixel and the text stays sharp.
/// Tiles that don't follow the content on an axis, such as a sticky header, a pinned column or a floating button, are
/// painted once at the edge of the image they stick to, and the content under them is filled in as it comes into view.
///
/// One instance belongs to one queue: frames go in on it, and the preview and result are read on it.
public final class ScrollStitcher {
    public enum ByteOrder: Sendable {
        case bgra
        case rgba
    }

    /// What the panel shows after a frame.
    public struct Update: Sendable {
        public let status: ScrollCaptureStatus
        /// The image so far, in pixels.
        public let size: CGSize
        /// Where the area is within the image, in pixels from its top left.
        public let viewport: CGRect
        /// Whether the image changed.
        public let changed: Bool
    }

    let width: Int
    let height: Int
    /// Device pixels per point: the box the greys average.
    let scale: Int
    let byteOrder: ByteOrder
    /// Tiles are `tile` device pixels square, 8 points, so a sticky band's edge is placed within half a line of text.
    let tile: Int
    let columns: Int
    let rows: Int
    /// The grey copies: level 1 at a pixel a point, level 2 at half that.
    private let width1: Int, height1: Int, width2: Int, height2: Int
    private let correlator: PhaseCorrelator

    private var previous: UnsafeMutablePointer<UInt8>
    private var current: UnsafeMutablePointer<UInt8>
    private var previous1: [Float]
    private var current1: [Float]
    private var previous2: [Float]
    private var current2: [Float]
    /// Per tile: whether the current frame has enough detail there to line up on.
    private var textured: [Bool]
    private var texturedCount = 0
    private var residuals: [Float]

    /// Per tile, from -1 (stays put) to 1 (follows the content) on each axis, and how often it changed in place.
    private var followX: [Float]
    private var followY: [Float]
    private var changing: [Float]
    /// Per tile, the edges it sticks to, as `Anchor` flags; 0 for content.
    private var flags: [UInt8]
    private var previousFlags: [UInt8]
    private var bands: [Band]
    private var previousBands: [Band]

    let canvas: ScrollCanvas
    /// Where the previous frame sits, in world pixels: the first frame is at the origin.
    private(set) var position = (x: 0, y: 0)
    private var previousPosition = (x: 0, y: 0)
    /// How far the view has been on each side, which sticky edges anchor to.
    private(set) var extremes = (minX: 0, maxX: 0, minY: 0, maxY: 0)
    private var lastShift = (x: 0, y: 0)
    private var frames = 0
    private var hitLimit = false
    public private(set) var status: ScrollCaptureStatus = .ready
    /// Set to collect `diagnostics` for each frame: what lined up and how well, for logs and tests.
    public var collectsDiagnostics = false
    public private(set) var diagnostics = ""

    // Thresholds on the 0–255 grey scale.
    private static let textureThreshold: Float = 8
    private static let agree2: Float = 10, cap2: Float = 24
    private static let agree1: Float = 14, cap1: Float = 32
    private static let agreeDevice: Float = 28, capDevice: Float = 56, gateDevice: Float = 14
    private static let voteMargin: Float = 8
    private static let peakCount = 5

    /// `scale` is device pixels per point. Frames must be `width` × `height` device pixels.
    public init(width: Int, height: Int, scale: Int, byteOrder: ByteOrder, limits: ScrollCaptureLimits = .standard) {
        precondition(width >= 16 && height >= 16 && scale >= 1)
        self.width = width
        self.height = height
        self.scale = scale
        self.byteOrder = byteOrder
        canvas = ScrollCanvas(limits: limits)
        tile = 8 * scale
        columns = (width + tile - 1) / tile
        rows = (height + tile - 1) / tile
        width1 = width / scale
        height1 = height / scale
        width2 = width1 / 2
        height2 = height1 / 2
        correlator = PhaseCorrelator(width: width2, height: height2)
        previous = .allocate(capacity: width * height * 4)
        current = .allocate(capacity: width * height * 4)
        previous1 = [Float](repeating: 0, count: width1 * height1)
        current1 = previous1
        previous2 = [Float](repeating: 0, count: width2 * height2)
        current2 = previous2
        let tiles = columns * rows
        textured = [Bool](repeating: false, count: tiles)
        residuals = [Float](repeating: .nan, count: tiles)
        followX = [Float](repeating: 0, count: tiles)
        followY = followX
        changing = followX
        flags = [UInt8](repeating: 0, count: tiles)
        previousFlags = flags
        bands = [Band](repeating: Band(), count: tiles)
        previousBands = bands
    }

    deinit {
        previous.deallocate()
        current.deallocate()
    }

    /// The image so far, in pixels.
    public var size: CGSize {
        canvas.seen.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }

    /// Where the area is within the image, in pixels from its top left.
    public var viewport: CGRect {
        let seen = canvas.seen ?? ScrollCanvas.Bounds(x0: position.x, y0: position.y, x1: position.x + width, y1: position.y + height)
        return CGRect(x: position.x - seen.x0, y: position.y - seen.y0, width: width, height: height)
    }

    // MARK: Frames

    /// Lines `frame` up with the last one and paints it. A frame of another size is ignored.
    public func process(_ frame: ScrollFrame) -> Update {
        guard frame.width == width, frame.height == height else {
            return update(changed: false)
        }
        diagnostics = ""
        lapMark = ContinuousClock.now
        copy(frame, into: current)
        greys()
        lap("copy+greys")
        frames += 1
        if frames == 1 {
            canvas.paintContent(current, width: width, height: height, at: (0, 0), rect: (0, 0, width, height))
            status = .ready
            swapFrames()
            return update(changed: true)
        }
        // Until this frame says otherwise, each tile sticks where it did.
        flags = previousFlags
        bands = previousBands
        texturedCount = measureTexture()
        lap("texture")
        guard texturedCount >= 10 else {
            status = .notEnough
            return update(changed: false)
        }
        let lined = bestShift()
        lap("bestShift")
        guard let lined else {
            // Nothing lined up: the content moved too far, or too much of it keeps changing in place.
            fail()
            return update(changed: false)
        }
        guard case let .value(settled) = lined else {
            status = .notEnough
            return update(changed: false)
        }
        let shift = settled
        let moved = shift.x != 0 || shift.y != 0
        let classified = classify(shift: shift)
        lap("classify")
        if !moved {
            if status.isWarning {
                status = .live
            }
            swapFrames()
            return update(changed: false)
        }
        lastShift = shift
        previousPosition = position
        position = (position.x + shift.x, position.y + shift.y)
        let before = extremes
        extremes.minX = min(extremes.minX, position.x)
        extremes.maxX = max(extremes.maxX, position.x)
        extremes.minY = min(extremes.minY, position.y)
        extremes.maxY = max(extremes.maxY, position.y)
        if classified {
            assignFlags()
        }
        lap("flags")
        splitBands(shift: shift)
        lap("split")
        let changed = paint(movedAnchors: before)
        lap("paint")
        status = hitLimit ? .sizeLimit : .live
        swapFrames()
        return update(changed: changed)
    }

    private func update(changed: Bool) -> Update {
        note("frame \(frames) → \(status) at \(position) size \(size)")
        return Update(status: status, size: size, viewport: viewport, changed: changed)
    }

    private func note(_ line: @autoclosure () -> String) {
        if collectsDiagnostics {
            diagnostics += line() + "\n"
        }
    }

    private var lapMark = ContinuousClock.now

    /// Notes how long since the last lap, for the diagnostics.
    private func lap(_ name: String) {
        if collectsDiagnostics {
            let now = ContinuousClock.now
            note("\(name) \(now - lapMark)")
            lapMark = now
        }
    }

    private func swapFrames() {
        swap(&previous, &current)
        swap(&previous1, &current1)
        swap(&previous2, &current2)
        swap(&previousFlags, &flags)
        swap(&previousBands, &bands)
    }

    private func fail() {
        // While nothing lines up, the last frame that did stays the reference, so scrolling back recovers.
        let shifts: [(Int, Int)] = [(0, 0), (lastShift.x, lastShift.y)]
        var unmatched = 0
        for t in 0..<(columns * rows) where textured[t] {
            var best: Float = .infinity
            for shift in shifts {
                let residual = deviceResidual(tile: t, shift: shift)
                if !residual.isNaN {
                    best = min(best, residual)
                }
            }
            if best > Self.agreeDevice {
                changing[t] = min(1, changing[t] + 0.34)
                if changing[t] >= 0.5 {
                    unmatched += 1
                }
            } else {
                changing[t] *= 0.5
            }
        }
        status = Float(unmatched) >= 0.4 * Float(texturedCount) ? .changing : .tooFar
    }

    private func copy(_ frame: ScrollFrame, into buffer: UnsafeMutablePointer<UInt8>) {
        let rowBytes = width * 4
        let source = frame.pixels.baseAddress!.assumingMemoryBound(to: UInt8.self)
        if frame.bytesPerRow == rowBytes {
            buffer.update(from: source, count: rowBytes * height)
            return
        }
        for y in 0..<height {
            (buffer + y * rowBytes).update(from: source + y * frame.bytesPerRow, count: rowBytes)
        }
    }

    /// The grey copies of the current frame: level 1 averages `scale` × `scale` device pixels, level 2 twice that.
    private func greys() {
        let scale = scale, width = width, width1 = width1, height1 = height1
        let divisor = Float(3 * scale * scale)
        let frame = current
        current1.withUnsafeMutableBufferPointer { grey in
            for y1 in 0..<height1 {
                for x1 in 0..<width1 {
                    var sum = 0
                    for dy in 0..<scale {
                        var p = frame + ((y1 * scale + dy) * width + x1 * scale) * 4
                        for _ in 0..<scale {
                            sum += Int(p[0]) + Int(p[1]) + Int(p[2])
                            p += 4
                        }
                    }
                    grey[y1 * width1 + x1] = Float(sum) / divisor
                }
            }
        }
        let width2 = width2, height2 = height2
        current1.withUnsafeBufferPointer { fine in
            current2.withUnsafeMutableBufferPointer { coarse in
                for y2 in 0..<height2 {
                    let row = y2 * 2 * width1
                    for x2 in 0..<width2 {
                        let i = row + x2 * 2
                        coarse[y2 * width2 + x2] = (fine[i] + fine[i + 1] + fine[i + width1] + fine[i + width1 + 1]) * 0.25
                    }
                }
            }
        }
    }

    /// Marks the tiles with enough detail to line up on: their mean absolute deviation at level 1 is above the threshold.
    private func measureTexture() -> Int {
        var count = 0
        let tile1 = 8, width1 = width1, height1 = height1
        current1.withUnsafeBufferPointer { grey in
            for r in 0..<rows {
                let y0 = r * tile1, y1 = min(y0 + tile1, height1)
                for c in 0..<columns {
                    let x0 = c * tile1, x1 = min(x0 + tile1, width1)
                    let t = r * columns + c
                    guard x1 > x0, y1 > y0 else {
                        textured[t] = false
                        continue
                    }
                    var sum: Float = 0
                    for y in y0..<y1 {
                        for x in x0..<x1 {
                            sum += grey[y * width1 + x]
                        }
                    }
                    let n = Float((x1 - x0) * (y1 - y0))
                    let mean = sum / n
                    var deviation: Float = 0
                    for y in y0..<y1 {
                        for x in x0..<x1 {
                            deviation += abs(grey[y * width1 + x] - mean)
                        }
                    }
                    textured[t] = deviation / n > Self.textureThreshold
                    if textured[t] {
                        count += 1
                    }
                }
            }
        }
        return count
    }

    // MARK: Lining up

    private enum Coarse: Equatable {
        case value((x: Int, y: Int))
        case ambiguous

        static func == (lhs: Coarse, rhs: Coarse) -> Bool {
            switch (lhs, rhs) {
            case (.ambiguous, .ambiguous): true
            case let (.value(a), .value(b)): a == b
            default: false
            }
        }
    }

    private struct Candidate {
        let shift: (x: Int, y: Int)
        let score: Float
        let agreement: Float
        let evaluable: Int
    }

    /// The device-pixel move that lines the frame up with the canvas. The correlation's peaks are each refined on
    /// the level-1 greys, which rank them; the best two well apart are then settled on the frame and the canvas
    /// themselves, to the device pixel, and judged there, where a move is exact and a table's digits can be told
    /// apart. The grey level only ranks: a move half a grey pixel off scores much worse there than its true, finer
    /// match does. Settling against the canvas rather than the last frame also anchors each frame to what's already
    /// painted, so small errors never add up. `nil` when nothing lines up, and `.ambiguous` when two moves well
    /// apart line up about as well, as on a pattern that repeats. A move over three quarters of the area is too far:
    /// the sliver left can match the wrong line.
    private func bestShift() -> Coarse? {
        var shifts: [(x: Int, y: Int)] = [(0, 0), (lastShift.x / scale, lastShift.y / scale)]
        for peak in correlator.peaks(from: previous2, to: current2, count: Self.peakCount) {
            shifts.append((peak.dx * 2, peak.dy * 2))
        }
        lap("peaks")
        var ranked: [Candidate] = []
        var seen = Set<Int>()
        let minimum = max(10, texturedCount / 5)
        // The peaks ranked cheaply on the half-size greys, so only the likeliest few are refined.
        var coarse: [Candidate] = []
        var tried: [(x: Int, y: Int)] = []
        for around in shifts where abs(around.x) * 4 <= width1 * 3 && abs(around.y) * 4 <= height1 * 3 {
            // A peak within a pixel of one already tried lands on the same answer, since refining reaches a pixel.
            guard !tried.contains(where: { abs($0.x - around.x) <= 1 && abs($0.y - around.y) <= 1 }) else {
                continue
            }
            tried.append(around)
            levelResiduals(level: 2, shift: (around.x / 2, around.y / 2), rowStep: 1)
            if let candidate = score(shift: around, agree: Self.agree2, cap: Self.cap2), candidate.evaluable >= minimum {
                coarse.append(candidate)
            }
        }
        for around in coarse.sorted(by: { $0.score < $1.score }).prefix(3).map(\.shift) {
            guard let candidate = refine(around), candidate.evaluable >= minimum else {
                continue
            }
            let key = (candidate.shift.x + 1 << 15) * 1 << 16 + (candidate.shift.y + 1 << 15)
            guard seen.insert(key).inserted else {
                continue
            }
            note("L1 \(candidate.shift) score \(candidate.score) agree \(candidate.agreement) n \(candidate.evaluable)/\(texturedCount)")
            ranked.append(candidate)
        }
        ranked.sort { $0.score < $1.score }
        lap("refine ×\(tried.count)")
        guard let first = ranked.first else {
            return nil
        }
        var settled = [settle((x: first.shift.x * scale, y: first.shift.y * scale))]
        // A rival well apart that scores nearly as well is settled too, to tell a repeating pattern; one that scores
        // far worse can't be the answer.
        if let rival = ranked.dropFirst().first(where: { max(abs($0.shift.x - first.shift.x), abs($0.shift.y - first.shift.y)) >= 6 }), rival.score < first.score * 2 + 2 {
            settled.append(settle((x: rival.shift.x * scale, y: rival.shift.y * scale)))
        }
        lap("settle ×\(settled.count)")
        let judged = settled.compactMap { $0 }.sorted { $0.score < $1.score }
        guard let best = judged.first, best.agreement >= 0.5, best.score <= Self.gateDevice, best.evaluable >= minimum else {
            return nil
        }
        if judged.count > 1, judged[1].score < best.score * 1.25 + 0.5 {
            return .ambiguous
        }
        return .value(best.shift)
    }

    /// The level-1 shift within a pixel of `around` with the least residual, searched on a third of the tiles and
    /// every fourth row, then scored on all of them.
    private func refine(_ around: (x: Int, y: Int)) -> Candidate? {
        var best = around
        var bestScore: Float = .infinity
        for dy in -1...1 {
            for dx in -1...1 {
                let shift = (x: around.x + dx, y: around.y + dy)
                levelResiduals(level: 1, shift: shift, rowStep: 4, every: 3)
                if let candidate = score(shift: shift, agree: Self.agree1, cap: Self.cap1), candidate.score < bestScore {
                    bestScore = candidate.score
                    best = shift
                }
            }
        }
        levelResiduals(level: 1, shift: best, rowStep: 4, every: 1)
        return score(shift: best, agree: Self.agree1, cap: Self.cap1)
    }

    /// The device-pixel shift within a grey pixel of `around` that fits the canvas best where the frame would land,
    /// over the tiles that follow the content. Where little of that is painted, as past the size limit, the previous
    /// frame stands in for the canvas.
    private func settle(_ around: (x: Int, y: Int)) -> Candidate? {
        var best: Candidate?
        let reach = max(1, scale - 1)
        let minimum = max(10, texturedCount / 5)
        for againstCanvas in [true, false] {
            // The search runs on a fifth of the tiles; the winner is then scored on all of them.
            func residuals(shift: (x: Int, y: Int), every: Int) {
                let at = (position.x + shift.x, position.y + shift.y)
                for t in 0..<(columns * rows) {
                    guard textured[t], previousFlags[t] == 0, (t / columns + t % columns) % every == 0 else {
                        self.residuals[t] = .nan
                        continue
                    }
                    self.residuals[t] = againstCanvas ? canvas.residual(of: current, width: width, height: height, tile: tileRect(t), at: at) : deviceResidual(tile: t, shift: shift)
                }
            }
            var bestShift = around
            var bestScore: Float = .infinity
            for dy in -reach...reach {
                for dx in -reach...reach {
                    let shift = (x: around.x + dx, y: around.y + dy)
                    residuals(shift: shift, every: 5)
                    if let candidate = score(shift: shift, agree: Self.agreeDevice, cap: Self.capDevice), candidate.score < bestScore {
                        bestScore = candidate.score
                        bestShift = shift
                    }
                }
            }
            residuals(shift: bestShift, every: 1)
            best = score(shift: bestShift, agree: Self.agreeDevice, cap: Self.capDevice)
            if let best, best.evaluable >= minimum {
                note("device \(best.shift) score \(best.score) agree \(best.agreement) n \(best.evaluable)\(againstCanvas ? "" : " vs frame")")
                return best
            }
            best = nil
        }
        return nil
    }

    /// The candidate's score over the textured tiles whose match lies inside the previous frame: the mean of the
    /// capped residuals, so a sticky header or a changing patch counts a bounded amount against it.
    private func score(shift: (x: Int, y: Int), agree: Float, cap: Float) -> Candidate? {
        var sum: Float = 0
        var evaluable = 0
        var agreed = 0
        for t in 0..<(columns * rows) where textured[t] {
            let residual = residuals[t]
            if residual.isNaN {
                continue
            }
            evaluable += 1
            sum += min(residual, cap)
            if residual < agree {
                agreed += 1
            }
        }
        guard evaluable > 0 else {
            return nil
        }
        return Candidate(shift: shift, score: sum / Float(evaluable), agreement: Float(agreed) / Float(evaluable), evaluable: evaluable)
    }

    /// The level-1 shift within a pixel of `around` with the least residual.
    private func refine(_ around: (x: Int, y: Int)) -> (x: Int, y: Int) {
        var best = around
        var bestScore: Float = .infinity
        for dy in -1...1 {
            for dx in -1...1 {
                let shift = (x: around.x + dx, y: around.y + dy)
                levelResiduals(level: 1, shift: shift, rowStep: 2)
                if let candidate = score(shift: shift, agree: Self.agree1, cap: Self.cap1), candidate.score < bestScore {
                    bestScore = candidate.score
                    best = shift
                }
            }
        }
        return best
    }

    /// Per-tile mean absolute differences between the current and previous grey copies at `level`, with the
    /// previous one moved by `shift`; NaN where the moved tile leaves the frame.
    private func levelResiduals(level: Int, shift: (x: Int, y: Int), rowStep: Int, every: Int = 1) {
        let (w, h, tileSize) = level == 1 ? (width1, height1, 8) : (width2, height2, 4)
        let cur = level == 1 ? current1 : current2
        let prev = level == 1 ? previous1 : previous2
        cur.withUnsafeBufferPointer { a in
            prev.withUnsafeBufferPointer { b in
                for r in 0..<rows {
                    let y0 = r * tileSize, y1 = min(y0 + tileSize, h)
                    for c in 0..<columns {
                        let t = r * columns + c
                        guard textured[t], (r + c) % every == 0 else {
                            residuals[t] = .nan
                            continue
                        }
                        let x0 = c * tileSize, x1 = min(x0 + tileSize, w)
                        guard x1 > x0, y1 > y0, x0 + shift.x >= 0, x1 + shift.x <= w, y0 + shift.y >= 0, y1 + shift.y <= h else {
                            residuals[t] = .nan
                            continue
                        }
                        var sum: Float = 0
                        var n = 0
                        var y = y0
                        while y < y1 {
                            let rowA = y * w, rowB = (y + shift.y) * w + shift.x
                            for x in x0..<x1 {
                                sum += abs(a[rowA + x] - b[rowB + x])
                            }
                            n += x1 - x0
                            y += rowStep
                        }
                        residuals[t] = sum / Float(n)
                    }
                }
            }
        }
    }

    // MARK: Sticky parts

    /// Flags for the edges a tile sticks to.
    enum Anchor {
        static let top: UInt8 = 1
        static let bottom: UInt8 = 2
        static let left: UInt8 = 4
        static let right: UInt8 = 8
    }

    /// Votes, per textured tile, on whether it followed the content on each axis this frame, and notes the tiles that
    /// matched nothing. Returns whether there was any evidence to vote on.
    private func classify(shift: (x: Int, y: Int)) -> Bool {
        let hypotheses: [(x: Int, y: Int)] = [(shift.x, shift.y), (0, 0), (shift.x, 0), (0, shift.y)]
        var voted = false
        for t in 0..<(columns * rows) where textured[t] {
            let rS = deviceResidual(tile: t, shift: hypotheses[0])
            let rZ = deviceResidual(tile: t, shift: hypotheses[1])
            let rX = deviceResidual(tile: t, shift: hypotheses[2])
            let rY = deviceResidual(tile: t, shift: hypotheses[3])
            // Without the move itself to test against, as at the edge the content came in from, there's nothing to say.
            guard !rS.isNaN else {
                continue
            }
            let least = [rS, rZ, rX, rY].filter { !$0.isNaN }.min() ?? rS
            if least > Self.agreeDevice {
                changing[t] = min(1, changing[t] + 0.34)
                continue
            }
            changing[t] *= 0.5
            // Moved in x: the hypotheses whose x component is the shift, S and X; stayed: Y and Z. Likewise for y.
            // A vote needs one hypothesis to fit and the other to fit clearly worse; a tile with a faint line in it
            // fits both about as well and says nothing.
            if shift.x != 0 {
                let follows = min(rS.orInfinite, rX.orInfinite), stays = min(rY.orInfinite, rZ.orInfinite)
                if min(follows, stays) <= Self.agreeDevice, abs(stays - follows) >= Self.voteMargin {
                    followX[t] = followX[t] * 0.6 + 0.4 * max(-1, min(1, (stays - follows) / (stays + follows + 4)))
                    voted = true
                }
            }
            if shift.y != 0 {
                let follows = min(rS.orInfinite, rY.orInfinite), stays = min(rX.orInfinite, rZ.orInfinite)
                if min(follows, stays) <= Self.agreeDevice, abs(stays - follows) >= Self.voteMargin {
                    followY[t] = followY[t] * 0.6 + 0.4 * max(-1, min(1, (stays - follows) / (stays + follows + 4)))
                    voted = true
                }
            }
        }
        return voted
    }

    /// The mean absolute difference, over every other row and fourth column of tile `t`, between the current frame and the previous
    /// one moved by `shift`; NaN where the moved tile leaves the frame.
    private func deviceResidual(tile t: Int, shift: (x: Int, y: Int)) -> Float {
        let rect = tileRect(t)
        let x0 = rect.x, y0 = rect.y, x1 = rect.x + rect.width, y1 = rect.y + rect.height
        guard x0 + shift.x >= 0, x1 + shift.x <= width, y0 + shift.y >= 0, y1 + shift.y <= height else {
            return .nan
        }
        var sum = 0
        var n = 0
        var y = y0
        while y < y1 {
            var a = current + (y * width + x0) * 4
            var b = previous + ((y + shift.y) * width + x0 + shift.x) * 4
            var x = x0
            while x < x1 {
                sum += abs(Int(a[0]) - Int(b[0])) + abs(Int(a[1]) - Int(b[1])) + abs(Int(a[2]) - Int(b[2]))
                a += 16
                b += 16
                x += 4
                n += 1
            }
            y += 2
        }
        return Float(sum) / Float(3 * n)
    }

    func tileRect(_ t: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let c = t % columns, r = t / columns
        let x = c * tile, y = r * tile
        return (x, y, min(tile, width - x), min(tile, height - y))
    }

    /// Settles each tile's edges from its votes. A tile without a vote of its own takes its row's vertical verdict and
    /// its column's horizontal one, from the nearest tiles that have one, since sticky parts are bands: a header's
    /// blank stretches scroll with its text, and a pinned column's empty cells stay with its full ones. A blank row
    /// or column with no verdict of its own sides with a sticky neighbour across it, since a band painted a little too
    /// wide costs nothing, while a band's blank edge painted as content would smear it over the page.
    private func assignFlags() {
        func settled(_ votes: [Float], _ t: Int) -> Float? {
            abs(votes[t]) >= 0.2 ? votes[t] : nil
        }
        /// The nearest settled votes before and after `t`, stepping by `step` within `range`.
        let all = 0..<(columns * rows)
        let unknown = Float.nan
        /// `values` with each unsettled entry filled from the nearest settled ones before and after it along `step`,
        /// within runs of `length`, combined by `combine`; a single sweep each way.
        func fill(_ values: [Float], step: Int, length: Int, runs: Int, runStride: Int, combine: (Float, Float) -> Float) -> [Float] {
            var before = [Float](repeating: unknown, count: values.count), after = before
            for run in 0..<runs {
                let start = run * runStride
                var last = unknown
                for i in 0..<length {
                    let t = start + i * step
                    if !values[t].isNaN { last = values[t] }
                    before[t] = last
                }
                last = unknown
                for i in stride(from: length - 1, through: 0, by: -1) {
                    let t = start + i * step
                    if !values[t].isNaN { last = values[t] }
                    after[t] = last
                }
            }
            return all.map { t in
                if !values[t].isNaN { return values[t] }
                switch (before[t].isNaN, after[t].isNaN) {
                case (false, false): return combine(before[t], after[t])
                case (false, true): return before[t]
                case (true, false): return after[t]
                default: return unknown
                }
            }
        }
        let ownY = all.map { settled(followY, $0) ?? unknown }, ownX = all.map { settled(followX, $0) ?? unknown }
        // First by a tile's own vote or its band's: the row for vertical behaviour, the column for horizontal.
        var vertical = fill(ownY, step: 1, length: columns, runs: rows, runStride: columns) { ($0 + $1) / 2 }
        var horizontal = fill(ownX, step: columns, length: rows, runs: columns, runStride: 1) { ($0 + $1) / 2 }
        // Then blank rows and columns from the nearest settled ones across them, siding with a sticky one.
        vertical = fill(vertical, step: columns, length: rows, runs: columns, runStride: 1) { min($0, $1) }
        horizontal = fill(horizontal, step: 1, length: columns, runs: rows, runStride: columns) { min($0, $1) }
        // Turning sticky takes a clear verdict; staying sticky takes less, so a tile on the fence doesn't flip each frame.
        for r in 0..<rows {
            for c in 0..<columns {
                let t = r * columns + c
                var flag: UInt8 = 0
                let wasVertical = previousFlags[t] & (Anchor.top | Anchor.bottom) != 0
                if !vertical[t].isNaN, vertical[t] < (wasVertical ? -0.1 : -0.2) {
                    flag |= r * 2 < rows ? Anchor.top : Anchor.bottom
                }
                let wasHorizontal = previousFlags[t] & (Anchor.left | Anchor.right) != 0
                if !horizontal[t].isNaN, horizontal[t] < (wasHorizontal ? -0.1 : -0.2) {
                    flag |= c * 2 < columns ? Anchor.left : Anchor.right
                }
                flags[t] = flag
            }
        }
    }

    // MARK: Painting

    /// How many pixel rows or columns of a tile belong to a sticky band on each side: all of them for a tile that
    /// sticks, none for content, and the rows up to the band's edge for a tile the edge runs through.
    struct Band: Equatable {
        var top: UInt8 = 0
        var bottom: UInt8 = 0
        var left: UInt8 = 0
        var right: UInt8 = 0
    }

    /// The x a part with `flags` lands at in the world, before its offset in the frame.
    private func anchorX(_ flag: UInt8, extremes: (minX: Int, maxX: Int, minY: Int, maxY: Int), position: (x: Int, y: Int)) -> Int {
        flag & Anchor.left != 0 ? extremes.minX : flag & Anchor.right != 0 ? extremes.maxX : position.x
    }

    private func anchorY(_ flag: UInt8, extremes: (minX: Int, maxX: Int, minY: Int, maxY: Int), position: (x: Int, y: Int)) -> Int {
        flag & Anchor.top != 0 ? extremes.minY : flag & Anchor.bottom != 0 ? extremes.maxY : position.y
    }

    /// Each tile's bands from its flags, then the edge of every band found to the pixel row across the tiles it runs
    /// through, so the tile on either side of the edge is painted in two parts. A band ends at the last strip that
    /// stays put: its border, shadow or colour step. A blank strip past that is painted as content, which costs
    /// nothing when it's the page's own colour; painted as the band it would land wherever the band's edge is, which
    /// is wrong once the view has moved away from it. When a frame can't tell, the edge found before stands.
    private func splitBands(shift: (x: Int, y: Int)) {
        for t in 0..<(columns * rows) {
            let rect = tileRect(t)
            var band = Band(
                top: flags[t] & Anchor.top != 0 ? UInt8(rect.height) : 0,
                bottom: flags[t] & Anchor.bottom != 0 ? UInt8(rect.height) : 0,
                left: flags[t] & Anchor.left != 0 ? UInt8(rect.width) : 0,
                right: flags[t] & Anchor.right != 0 ? UInt8(rect.width) : 0
            )
            if flags[t] & (Anchor.top | Anchor.bottom) == previousFlags[t] & (Anchor.top | Anchor.bottom) {
                band.top = previousBands[t].top
                band.bottom = previousBands[t].bottom
            }
            if flags[t] & (Anchor.left | Anchor.right) == previousFlags[t] & (Anchor.left | Anchor.right) {
                band.left = previousBands[t].left
                band.right = previousBands[t].right
            }
            bands[t] = band
        }
        // Vertical edges, between a tile and the one below it, over runs of columns where the same pair of classes
        // meets; only a move with a vertical part says anything about them.
        for r in 0..<(rows - 1) where shift.y != 0 {
            var c = 0
            while c < columns {
                let t = r * columns + c, u = t + columns
                let pair = (flags[t] & (Anchor.top | Anchor.bottom), flags[u] & (Anchor.top | Anchor.bottom))
                var end = c
                while end + 1 < columns, (flags[r * columns + end + 1] & (Anchor.top | Anchor.bottom), flags[u + end + 1 - c] & (Anchor.top | Anchor.bottom)) == pair {
                    end += 1
                }
                let topEdge = pair.0 & Anchor.top != 0 && pair.1 & Anchor.top == 0
                let bottomEdge = pair.0 & Anchor.bottom == 0 && pair.1 & Anchor.bottom != 0
                if topEdge || bottomEdge {
                    let first = tileRect(t), last = tileRect(r * columns + end), below = tileRect(u)
                    let verdicts = stripVerdicts(x0: first.x, x1: last.x + last.width, y0: first.y, y1: below.y + below.height, acrossRows: true, shift: shift)
                    if topEdge, let edge = verdicts.lastIndex(where: { $0 == .stays }).map({ ($0 + 1) * 2 }) {
                        for k in c...end {
                            let above = r * columns + k
                            bands[above].top = UInt8(min(edge, first.height))
                            bands[above + columns].top = UInt8(max(0, min(below.height, edge - first.height)))
                        }
                    }
                    if bottomEdge, let edge = verdicts.firstIndex(where: { $0 == .stays }).map({ $0 * 2 }) {
                        for k in c...end {
                            let above = r * columns + k
                            bands[above].bottom = UInt8(max(0, first.height - edge))
                            bands[above + columns].bottom = UInt8(below.height - max(0, min(below.height, edge - first.height)))
                        }
                    }
                }
                c = end + 1
            }
        }
        // Horizontal edges, between a tile and the one to its right, over runs of rows.
        for c in 0..<(columns - 1) where shift.x != 0 {
            var r = 0
            while r < rows {
                let t = r * columns + c, u = t + 1
                let pair = (flags[t] & (Anchor.left | Anchor.right), flags[u] & (Anchor.left | Anchor.right))
                var end = r
                while end + 1 < rows, (flags[(end + 1) * columns + c] & (Anchor.left | Anchor.right), flags[(end + 1) * columns + c + 1] & (Anchor.left | Anchor.right)) == pair {
                    end += 1
                }
                let leftEdge = pair.0 & Anchor.left != 0 && pair.1 & Anchor.left == 0
                let rightEdge = pair.0 & Anchor.right == 0 && pair.1 & Anchor.right != 0
                if leftEdge || rightEdge {
                    let first = tileRect(t), last = tileRect(end * columns + c), beside = tileRect(u)
                    let verdicts = stripVerdicts(x0: first.x, x1: beside.x + beside.width, y0: first.y, y1: last.y + last.height, acrossRows: false, shift: shift)
                    if leftEdge, let edge = verdicts.lastIndex(where: { $0 == .stays }).map({ ($0 + 1) * 2 }) {
                        for k in r...end {
                            let left = k * columns + c
                            bands[left].left = UInt8(min(edge, first.width))
                            bands[left + 1].left = UInt8(max(0, min(beside.width, edge - first.width)))
                        }
                    }
                    if rightEdge, let edge = verdicts.firstIndex(where: { $0 == .stays }).map({ $0 * 2 }) {
                        for k in r...end {
                            let left = k * columns + c
                            bands[left].right = UInt8(max(0, first.width - edge))
                            bands[left + 1].right = UInt8(beside.width - max(0, min(beside.width, edge - first.width)))
                        }
                    }
                }
                r = end + 1
            }
        }
    }

    private enum Verdict {
        case stays, follows, unsure
    }

    /// For each two-pixel strip of the frame rect, across its rows or its columns, whether what's there stayed put or
    /// followed the content this frame, or whether both fit, as they do where the strip is blank in both frames. A
    /// strip needs no detail of its own: a border that fills it still differs from what the content would have put
    /// there.
    private func stripVerdicts(x0: Int, x1: Int, y0: Int, y1: Int, acrossRows: Bool, shift: (x: Int, y: Int)) -> [Verdict] {
        let count = acrossRows ? (y1 - y0) / 2 : (x1 - x0) / 2
        var verdicts: [Verdict] = []
        for i in 0..<count {
            let rect = acrossRows ? (x0, y0 + i * 2, x1, y0 + i * 2 + 2) : (x0 + i * 2, y0, x0 + i * 2 + 2, y1)
            let rS = stripResidual(rect, shift: shift), rZ = stripResidual(rect, shift: (0, 0))
            let rX = stripResidual(rect, shift: (shift.x, 0)), rY = stripResidual(rect, shift: (0, shift.y))
            guard !rS.isNaN else {
                verdicts.append(.unsure)
                continue
            }
            let stays = acrossRows ? min(rZ.orInfinite, rX.orInfinite) : min(rZ.orInfinite, rY.orInfinite)
            let follows = acrossRows ? min(rS.orInfinite, rY.orInfinite) : min(rS.orInfinite, rX.orInfinite)
            // A clear margin either way; a tiny move leaves the two close, and then the edge found before stands.
            if stays <= Self.agreeDevice, stays * 1.5 + 2 < follows {
                verdicts.append(.stays)
            } else if follows <= Self.agreeDevice, follows * 1.5 + 2 < stays {
                verdicts.append(.follows)
            } else {
                verdicts.append(.unsure)
            }
        }
        return verdicts
    }

    /// The mean absolute difference over a strip between the current frame and the previous one moved by `shift`,
    /// sampling every other pixel; NaN where the moved strip leaves the frame.
    private func stripResidual(_ rect: (x0: Int, y0: Int, x1: Int, y1: Int), shift: (x: Int, y: Int)) -> Float {
        guard rect.x0 + shift.x >= 0, rect.x1 + shift.x <= width, rect.y0 + shift.y >= 0, rect.y1 + shift.y <= height else {
            return .nan
        }
        var sum = 0, n = 0
        var y = rect.y0
        while y < rect.y1 {
            var x = rect.x0
            while x < rect.x1 {
                let a = current + (y * width + x) * 4
                let b = previous + ((y + shift.y) * width + x + shift.x) * 4
                sum += abs(Int(a[0]) - Int(b[0])) + abs(Int(a[1]) - Int(b[1])) + abs(Int(a[2]) - Int(b[2]))
                n += 1
                x += 2
            }
            y += 1
        }
        return n > 0 ? Float(sum) / Float(3 * n) : .nan
    }

    /// Calls `body` for each run of pixels in tile `t` that land together: per pixel row, the columns of its left
    /// band, its middle and its right band, each with the flags of the edges they stick to, 0 for content.
    private func forEachRun(of t: Int, bands band: Band, _ body: (_ y: Int, _ x0: Int, _ x1: Int, _ flags: UInt8) -> Void) {
        let rect = tileRect(t)
        for row in 0..<rect.height {
            let rowFlag: UInt8 = row < Int(band.top) ? Anchor.top : row >= rect.height - Int(band.bottom) ? Anchor.bottom : 0
            let parts: [(Int, Int, UInt8)] = [
                (0, Int(band.left), Anchor.left),
                (Int(band.left), rect.width - Int(band.right), 0),
                (rect.width - Int(band.right), rect.width, Anchor.right),
            ]
            for part in parts where part.1 > part.0 {
                body(rect.y + row, rect.x + part.0, rect.x + part.1, rowFlag | part.2)
            }
        }
    }

    /// Paints the current frame: content where the view is, sticky parts at their edges, after clearing sticky paint
    /// whose edge moved. Returns whether the image changed.
    private func paint(movedAnchors before: (minX: Int, maxX: Int, minY: Int, maxY: Int)) -> Bool {
        // A tile that just turned sticky was painted as content last frame; that paint becomes sticky paint, which the
        // moved-edge clearing below takes away if it's in the wrong place. One that stops being sticky, or sticks to
        // another edge, loses its sticky paint, and the content under it fills in as it's seen.
        for t in 0..<(columns * rows) where flags[t] != previousFlags[t] {
            if previousFlags[t] != 0 {
                guard flags[t] == 0 else {
                    // Still sticky, to other edges: its old paint stays until the edge it was anchored to moves.
                    continue
                }
                forEachRun(of: t, bands: previousBands[t]) { y, x0, x1, runFlags in
                    guard runFlags != 0 else {
                        return
                    }
                    let at = (x: anchorX(runFlags, extremes: before, position: previousPosition), y: anchorY(runFlags, extremes: before, position: previousPosition))
                    canvas.clearPinned(rect: (at.x + x0, at.y + y, x1 - x0, 1), flags: runFlags)
                }
            } else {
                // Only what this tile painted as content last frame: a part that was a band already went elsewhere.
                let rect = tileRect(t), was = previousBands[t]
                forEachRun(of: t, bands: bands[t]) { y, x0, x1, runFlags in
                    let row = y - rect.y
                    guard runFlags != 0, row >= Int(was.top), row < rect.height - Int(was.bottom) else {
                        return
                    }
                    let from = max(x0, rect.x + Int(was.left)), to = min(x1, rect.x + rect.width - Int(was.right))
                    if to > from {
                        canvas.markPinned(rect: (previousPosition.x + from, previousPosition.y + y, to - from, 1), flags: runFlags)
                    }
                }
            }
        }
        var movedFlags: UInt8 = 0
        if extremes.minX != before.minX { movedFlags |= Anchor.left }
        if extremes.maxX != before.maxX { movedFlags |= Anchor.right }
        if extremes.minY != before.minY { movedFlags |= Anchor.top }
        if extremes.maxY != before.maxY { movedFlags |= Anchor.bottom }
        if movedFlags != 0 {
            canvas.clearPinned(anchoredTo: movedFlags)
        }
        // The canvas must hold the view and the edges its sticky parts go to; what doesn't fit within the limits is
        // left out.
        var needed = ScrollCanvas.Bounds(x0: position.x, y0: position.y, x1: position.x + width, y1: position.y + height)
        var used: UInt8 = 0
        for t in 0..<(columns * rows) {
            used |= flags[t]
        }
        for flag in [Anchor.top, Anchor.bottom, Anchor.left, Anchor.right] where used & flag != 0 {
            let x = anchorX(flag, extremes: extremes, position: position), y = anchorY(flag, extremes: extremes, position: position)
            needed = needed.union(ScrollCanvas.Bounds(x0: x, y0: y, x1: x + width, y1: y + height))
        }
        if !canvas.ensure(needed) {
            hitLimit = true
        }
        // Each pixel row is painted in runs of pixels that land together: content with the view, and each sticky
        // part at its edges.
        var content: ScrollCanvas.Bounds?
        var pinned: ScrollCanvas.Bounds?
        for r in 0..<rows {
            let tileHeight = min(tile, height - r * tile)
            for row in 0..<tileHeight {
                let y = r * tile + row
                var runStart = 0
                var runFlags: UInt8 = 0
                var runOpen = false
                func flush(to end: Int) {
                    guard runOpen, end > runStart else {
                        return
                    }
                    let at = (x: anchorX(runFlags, extremes: extremes, position: position), y: anchorY(runFlags, extremes: extremes, position: position))
                    let painted = runFlags == 0
                        ? canvas.paintContentRow(current, width: width, y: y, x0: runStart, x1: end, at: at)
                        : canvas.paintPinnedRow(current, width: width, y: y, x0: runStart, x1: end, at: at, flags: runFlags)
                    if let painted {
                        if runFlags == 0 {
                            content = content.map { $0.union(painted) } ?? painted
                        } else {
                            pinned = pinned.map { $0.union(painted) } ?? painted
                        }
                    }
                }
                for c in 0..<columns {
                    let t = r * columns + c
                    let band = bands[t]
                    let tileWidth = min(tile, width - c * tile), x0 = c * tile
                    let rowFlag: UInt8 = row < Int(band.top) ? Anchor.top : row >= tileHeight - Int(band.bottom) ? Anchor.bottom : 0
                    let parts: [(Int, Int, UInt8)] = [
                        (0, Int(band.left), Anchor.left),
                        (Int(band.left), tileWidth - Int(band.right), 0),
                        (tileWidth - Int(band.right), tileWidth, Anchor.right),
                    ]
                    for part in parts where part.1 > part.0 {
                        let partFlags = rowFlag | part.2
                        if !runOpen || partFlags != runFlags {
                            flush(to: x0 + part.0)
                            runStart = x0 + part.0
                            runFlags = partFlags
                            runOpen = true
                        }
                    }
                }
                flush(to: width)
            }
        }
        if let content {
            // Where the last frame already painted, the preview changes too little to redraw every time.
            canvas.painted(content, refreshingOutside: ScrollCanvas.Bounds(x0: previousPosition.x, y0: previousPosition.y, x1: previousPosition.x + width, y1: previousPosition.y + height))
        }
        if let pinned {
            canvas.painted(pinned)
        }
        return content != nil || pinned != nil
    }

    // MARK: Output

    /// The image so far at an eighth of its size, with unseen parts clear, for the panel's preview.
    public func preview() -> CGImage? {
        canvas.previewImage(byteOrder: byteOrder)
    }

    /// The stitched image: every pixel seen, with the rest clear. `colorSpace` is the frames'.
    public func image(colorSpace: CGColorSpace? = nil) -> CGImage? {
        canvas.image(byteOrder: byteOrder, colorSpace: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
    }
}

private extension Float {
    var orInfinite: Float { isNaN ? .infinity : self }
}
