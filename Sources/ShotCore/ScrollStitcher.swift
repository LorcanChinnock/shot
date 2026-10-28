import Foundation

/// Joins the frames of a scrolling area into one image, whichever way the content moves: down, up, sideways or at an
/// angle, in any order. Each frame is matched to the one before it to find how far the content moved, and only what
/// hasn't been seen yet is added to a canvas that grows to fit.
///
/// Whatever stays put while the content moves, such as a sticky header or footer or a floating button, is painted once.
/// The content it hides is filled in when it scrolls into view, and scrolling back over what's already there adds nothing.
public struct ScrollStitcher: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The frame showed something new, which was added.
        case extended
        /// The frame showed nothing new: the content didn't move, or moved back over what was captured.
        case unchanged
        /// The content moved so far that the frame has nothing in common with the last good one. Nothing was added, and
        /// the next frame is matched to the last good one, so scrolling back recovers.
        case tooFar
        /// Part of the frame kept changing from one frame to the next without scrolling, such as a playing video.
        /// Nothing was added.
        case moving
        /// The frame is too plain, or repeats too much, to tell how far it moved. Nothing was added.
        case featureless
        /// The image reached its size limit. What fits was added, and later frames add nothing.
        case limit
    }

    /// The longest side of the image, in pixels.
    public static let defaultMaxLength = 30_000
    /// The most pixels the image may hold, so a wide and tall capture can't use all the memory.
    public static let defaultMaxPixels = 100_000_000

    public let maxLength: Int
    public let maxPixels: Int

    /// Frames in a row that must keep changing in place before they are called moving rather than too far.
    private static let movingFrames = 4

    private let scale: CGFloat
    private let frameWidth: Int
    private let frameHeight: Int
    private var last: ScrollFrame
    private var lastLuma: ScrollMotion.Luma
    private var previous: ScrollFrame
    private var changingFrames = 0
    private var canvas: Canvas
    /// Where the last good frame's top-left corner sits on the canvas.
    private var placement = (x: 0, y: 0)
    /// Rows at the top and columns at the left that stay put while the content scrolls the other way, as a spreadsheet's
    /// header row does when it scrolls only sideways. Their pixels belong at the canvas's own edge, not wherever the
    /// frame is placed.
    private var pinned = (top: 0, left: 0)
    private var full = false

    public init(first frame: Bitmap, maxLength: Int = ScrollStitcher.defaultMaxLength, maxPixels: Int = ScrollStitcher.defaultMaxPixels) {
        self.maxLength = maxLength
        self.maxPixels = maxPixels
        scale = frame.scale
        frameWidth = frame.width
        frameHeight = frame.height
        let first = ScrollFrame(frame)
        last = first
        previous = first
        lastLuma = ScrollMotion.luma(of: first)
        canvas = Canvas(width: frame.width, height: frame.height)
        canvas.paint(first, at: (0, 0), level: .tentative)
    }

    /// The image's width and height in pixels so far.
    public var size: (width: Int, height: Int) {
        (canvas.width, canvas.height)
    }

    /// The image so far.
    public var result: Bitmap {
        canvas.bitmap(in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height), scale: scale)
    }

    /// A part of the image no larger than `aspect` (width over height) allows, centred on the newest frame and as wide
    /// as one frame, so a preview shows what was captured last and stays readable however big the image grows.
    public func preview(aspect: Double) -> Bitmap {
        var width = min(canvas.width, frameWidth)
        var height = min(canvas.height, max(1, Int(Double(width) / aspect)))
        width = min(width, max(1, Int(Double(height) * aspect)))
        height = min(height, canvas.height)
        let midX = placement.x + frameWidth / 2, midY = placement.y + frameHeight / 2
        let x = min(max(midX - width / 2, 0), canvas.width - width)
        let y = min(max(midY - height / 2, 0), canvas.height - height)
        return canvas.bitmap(in: CGRect(x: x, y: y, width: width, height: height), scale: scale)
    }

    public mutating func add(_ frame: Bitmap) -> Outcome {
        if full {
            return .limit
        }
        guard frame.width == frameWidth, frame.height == frameHeight else {
            return .moving
        }
        let current = ScrollFrame(frame)
        defer { previous = current }
        if current.pixels == last.pixels {
            changingFrames = 0
            return .unchanged
        }
        let luma = ScrollMotion.luma(of: current)
        switch ScrollMotion.estimate(from: last, lastLuma, to: current, luma) {
        case let .shift(dx, dy):
            changingFrames = 0
            return place(current, luma, shiftedBy: (dx, dy))
        case .still:
            // Something changed without the content moving. A caret or a hover is nothing; a video keeps on changing.
            return failure(for: current, whenQuiet: .unchanged)
        case .featureless:
            return .featureless
        case .lost:
            return failure(for: current, whenQuiet: .tooFar)
        }
    }

    /// Why `current` can't be lined up with the last good frame. A frame that matches the one just before it in most
    /// places, again and again, is changing in place. Any other is the content having scrolled out of reach, and the
    /// frames after it are the same as each other once the scrolling stops.
    private mutating func failure(for current: ScrollFrame, whenQuiet quiet: Outcome) -> Outcome {
        let still = similarity(previous, current)
        guard still < 0.999, still >= 0.5 else {
            changingFrames = 0
            return quiet
        }
        changingFrames += 1
        return changingFrames >= Self.movingFrames ? .moving : quiet
    }

    /// The share of the pixels, sampled across the frame, that are the same in both frames.
    private func similarity(_ a: ScrollFrame, _ b: ScrollFrame) -> Double {
        let stepX = max(1, a.width / 160), stepY = max(1, a.height / 220)
        var same = 0, total = 0
        for y in stride(from: 0, to: a.height, by: stepY) {
            for x in stride(from: 0, to: a.width, by: stepX) {
                total += 1
                if a.pixels[y * a.width + x] == b.pixels[y * a.width + x] {
                    same += 1
                }
            }
        }
        return Double(same) / Double(total)
    }

    private mutating func place(_ current: ScrollFrame, _ luma: ScrollMotion.Luma, shiftedBy shift: (dx: Int, dy: Int)) -> Outcome {
        let x = placement.x + shift.dx, y = placement.y + shift.dy
        let left = min(x, 0), top = min(y, 0)
        let right = max(canvas.width, x + frameWidth), bottom = max(canvas.height, y + frameHeight)
        let (width, height) = (right - left, bottom - top)
        guard width <= maxLength, height <= maxLength, width * height <= maxPixels else {
            full = true
            return .limit
        }
        canvas.grow(left: -left, top: -top, right: right - canvas.width, bottom: bottom - canvas.height)
        let origin = (x - left, y - top)
        learnPinned(in: current, shiftedBy: shift)
        let painted = canvas.add(current, over: last, shiftedBy: shift, at: origin, pinned: pinned)
        placement = origin
        last = current
        lastLuma = luma
        return painted ? .extended : .unchanged
    }

    /// Learns from a move along one axis which rows or columns stayed put, since a header that scrolls with the content
    /// one way only shows it when the content moves the other way.
    private mutating func learnPinned(in current: ScrollFrame, shiftedBy shift: (dx: Int, dy: Int)) {
        let (w, h) = (frameWidth, frameHeight)
        if shift.dx == 0, shift.dy != 0 {
            let run = Self.stayingRun(count: h / 2, length: w) { line, i in
                let ys = line + shift.dy
                let same = last.pixels[line * w + i] == current.pixels[line * w + i]
                let moved: Bool? = ys >= 0 && ys < h ? last.pixels[ys * w + i] == current.pixels[line * w + i] : nil
                return (same, moved)
            }
            pinned.top = max(pinned.top, run)
        } else if shift.dy == 0, shift.dx != 0 {
            let run = Self.stayingRun(count: w / 2, length: h) { line, i in
                let xs = line + shift.dx
                let same = last.pixels[i * w + line] == current.pixels[i * w + line]
                let moved: Bool? = xs >= 0 && xs < w ? last.pixels[i * w + xs] == current.pixels[i * w + line] : nil
                return (same, moved)
            }
            pinned.left = max(pinned.left, run)
        }
    }

    /// How many leading lines (rows or columns) of a frame stayed put, ending at the last one that proves it: one that
    /// is the same in both frames but not the same as where the content moved from, which a plain colour never is.
    private static func stayingRun(count: Int, length: Int, sample: (_ line: Int, _ index: Int) -> (same: Bool, moved: Bool?)) -> Int {
        var run = 0
        for line in 0..<count {
            var same = 0, moved = 0, comparable = 0
            for i in 0..<length {
                let pixel = sample(line, i)
                if pixel.same {
                    same += 1
                }
                if let m = pixel.moved {
                    comparable += 1
                    if m {
                        moved += 1
                    }
                }
            }
            guard Double(same) >= Double(length) * 0.98 else {
                break
            }
            if comparable > 0, Double(moved) <= Double(comparable) * 0.95 {
                run = line + 1
            }
        }
        return run
    }

    // MARK: Canvas

    /// How sure a canvas pixel is. A frame's pixels start as a guess, since until the content moves nothing says what
    /// stays put; content seen to scroll replaces a guess but never other content.
    private enum Level: UInt8 {
        case empty = 0
        case tentative = 1
        case content = 2
    }

    private struct Canvas: Sendable {
        private(set) var width: Int
        private(set) var height: Int
        private var stride: Int
        private var pixels: [UInt32]
        private var levels: [UInt8]

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            stride = width
            pixels = [UInt32](repeating: 0, count: width * height)
            levels = [UInt8](repeating: 0, count: width * height)
        }

        /// Makes room on each side, keeping what is there where it is relative to the new edges.
        mutating func grow(left: Int, top: Int, right: Int, bottom: Int) {
            guard left > 0 || top > 0 || right > 0 || bottom > 0 else {
                return
            }
            let newWidth = width + left + right, newHeight = height + top + bottom
            if left == 0, top == 0, newWidth <= stride {
                let extra = (newHeight - height) * stride
                pixels.append(contentsOf: repeatElement(0, count: extra))
                levels.append(contentsOf: repeatElement(0, count: extra))
            } else {
                // Wider than the rows allow, or growing up or left: lay the canvas out again, with room to spare to the
                // right so a steady scroll sideways doesn't lay it out for every frame.
                let newStride = left > 0 || newWidth > stride ? max(newWidth, newWidth + newWidth / 4) : stride
                var newPixels = [UInt32](repeating: 0, count: newStride * newHeight)
                var newLevels = [UInt8](repeating: 0, count: newStride * newHeight)
                for y in 0..<height {
                    let from = y * stride, to = (y + top) * newStride + left
                    newPixels.replaceSubrange(to..<to + width, with: pixels[from..<from + width])
                    newLevels.replaceSubrange(to..<to + width, with: levels[from..<from + width])
                }
                pixels = newPixels
                levels = newLevels
                stride = newStride
            }
            width = newWidth
            height = newHeight
        }

        /// Paints all of `frame` at `origin`.
        mutating func paint(_ frame: ScrollFrame, at origin: (x: Int, y: Int), level: Level) {
            for y in 0..<frame.height {
                let to = (origin.y + y) * stride + origin.x
                pixels.replaceSubrange(to..<to + frame.width, with: frame.pixels[y * frame.width..<(y + 1) * frame.width])
                for x in 0..<frame.width {
                    levels[to + x] = level.rawValue
                }
            }
        }

        /// Adds what `frame` shows that `before` didn't, given that pixel (x, y) of `frame` was pixel (x + dx, y + dy) of
        /// `before`, with `frame` placed at `origin`. `true` when something was painted.
        ///
        /// A pixel that is the same in `before` at the shifted place is known already. One that is the same in `before`
        /// at its own place stays put on screen, so it is only a guess for any canvas pixel that is empty. One with
        /// nothing in `before` to compare with, or whose shifted place in `before` stayed put (so something was hiding
        /// the content there), is new content. Anything else changed in place, and is left alone. The `pinned` top rows and
        /// left columns go to the canvas's own edge.
        mutating func add(_ frame: ScrollFrame, over before: ScrollFrame, shiftedBy shift: (dx: Int, dy: Int), at origin: (x: Int, y: Int), pinned: (top: Int, left: Int)) -> Bool {
            let (w, h) = (frame.width, frame.height)
            var stays = [Bool](repeating: false, count: w * h)
            for i in 0..<w * h {
                stays[i] = frame.pixels[i] == before.pixels[i]
            }
            var painted = false
            for y in 0..<h {
                let ys = y + shift.dy
                for x in 0..<w {
                    let i = y * w + x, value = frame.pixels[i], xs = x + shift.dx
                    let inside = xs >= 0 && xs < w && ys >= 0 && ys < h
                    if inside, before.pixels[ys * w + xs] == value {
                        continue
                    }
                    let at = (y < pinned.top ? y : origin.y + y) * stride + (x < pinned.left ? x : origin.x + x)
                    if stays[i] {
                        if levels[at] == Level.empty.rawValue {
                            pixels[at] = value
                            levels[at] = Level.tentative.rawValue
                            painted = true
                        }
                    } else if !inside || stays[ys * w + xs] {
                        if levels[at] < Level.content.rawValue {
                            painted = painted || pixels[at] != value || levels[at] == Level.empty.rawValue
                            pixels[at] = value
                            levels[at] = Level.content.rawValue
                        }
                    }
                }
            }
            return painted
        }

        func bitmap(in rect: CGRect, scale: CGFloat) -> Bitmap {
            let (x, y, w, h) = (Int(rect.minX), Int(rect.minY), Int(rect.width), Int(rect.height))
            var data = Data(count: w * h * 4)
            data.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Void in
                pixels.withUnsafeBufferPointer { source in
                    for row in 0..<h {
                        let from = (y + row) * stride + x
                        let destination = out.baseAddress!.advanced(by: row * w * 4)
                        destination.copyMemory(from: source.baseAddress!.advanced(by: from), byteCount: w * 4)
                    }
                }
            }
            return Bitmap(width: w, height: h, scale: scale, pixels: data)!
        }
    }
}
