import CoreGraphics
import Foundation

/// The growing image a scrolling capture paints into: 4 bytes a pixel in the frames' byte order, in world pixels,
/// where the first frame sits at the origin. The alpha byte says who painted a pixel: 0 for nobody, 255 for content,
/// and 240 plus its `ScrollStitcher.Anchor` flags for a sticky part, so sticky paint can be cleared when the edge it
/// sticks to moves, and never covers content that's been seen. An eighth-size copy is kept up for the preview.
final class ScrollCanvas {
    struct Bounds: Equatable {
        var x0: Int, y0: Int, x1: Int, y1: Int

        var width: Int { x1 - x0 }
        var height: Int { y1 - y0 }
        var isEmpty: Bool { x1 <= x0 || y1 <= y0 }

        func union(_ other: Bounds) -> Bounds {
            Bounds(x0: min(x0, other.x0), y0: min(y0, other.y0), x1: max(x1, other.x1), y1: max(y1, other.y1))
        }

        func intersection(_ other: Bounds) -> Bounds {
            Bounds(x0: max(x0, other.x0), y0: max(y0, other.y0), x1: min(x1, other.x1), y1: min(y1, other.y1))
        }

        func contains(_ other: Bounds) -> Bool {
            other.x0 >= x0 && other.y0 >= y0 && other.x1 <= x1 && other.y1 <= y1
        }
    }

    private var buffer: UnsafeMutablePointer<UInt8>?
    /// The canvas's place in the world, its origin and size multiples of the preview cell.
    private(set) var bounds = Bounds(x0: 0, y0: 0, x1: 0, y1: 0)
    private var mip: [UInt8] = []
    private var mipWidth = 0
    private var mipHeight = 0
    /// The world rect holding every pixel painted so far.
    private(set) var seen: Bounds?
    /// Where each kind of sticky paint lies, by its alpha code.
    private var pinnedBounds: [UInt8: Bounds] = [:]

    static let cell = 8
    private static let margin = 512
    private let limits: ScrollCaptureLimits

    init(limits: ScrollCaptureLimits = .standard) {
        self.limits = limits
    }

    deinit {
        buffer?.deallocate()
    }

    private var stride: Int { bounds.width * 4 }

    // MARK: Size

    /// Makes the canvas hold `needed`, growing by a margin so it isn't reallocated every frame. False when the limits
    /// kept part of it out.
    @discardableResult
    func ensure(_ needed: Bounds) -> Bool {
        if buffer != nil, bounds.contains(needed) {
            return true
        }
        let cell = Self.cell
        func floorCell(_ v: Int) -> Int { Int((Double(v) / Double(cell)).rounded(.down)) * cell }
        func ceilCell(_ v: Int) -> Int { Int((Double(v) / Double(cell)).rounded(.up)) * cell }
        var wanted: Bounds
        if buffer == nil {
            wanted = Bounds(x0: floorCell(needed.x0), y0: floorCell(needed.y0), x1: ceilCell(needed.x1), y1: ceilCell(needed.y1))
        } else {
            let growX = max(Self.margin, bounds.width / 4), growY = max(Self.margin, bounds.height / 4)
            wanted = bounds
            if needed.x0 < bounds.x0 { wanted.x0 = floorCell(needed.x0 - growX) }
            if needed.x1 > bounds.x1 { wanted.x1 = ceilCell(needed.x1 + growX) }
            if needed.y0 < bounds.y0 { wanted.y0 = floorCell(needed.y0 - growY) }
            if needed.y1 > bounds.y1 { wanted.y1 = ceilCell(needed.y1 + growY) }
            if !fits(wanted) {
                // No margin, then.
                wanted = Bounds(x0: min(bounds.x0, floorCell(needed.x0)), y0: min(bounds.y0, floorCell(needed.y0)), x1: max(bounds.x1, ceilCell(needed.x1)), y1: max(bounds.y1, ceilCell(needed.y1)))
            }
        }
        let old = buffer == nil ? wanted : bounds
        var limited = false
        if !fits(wanted) {
            limited = true
            (wanted.x0, wanted.x1) = Self.clamp(old: (old.x0, old.x1), wanted: (wanted.x0, wanted.x1), to: limits.maxSide)
            (wanted.y0, wanted.y1) = Self.clamp(old: (old.y0, old.y1), wanted: (wanted.y0, wanted.y1), to: limits.maxSide)
            if wanted.width * wanted.height > limits.maxPixels {
                // Trim the axis that grew this time; the other keeps what it has.
                let grewY = wanted.height > old.height
                if grewY {
                    (wanted.y0, wanted.y1) = Self.clamp(old: (old.y0, old.y1), wanted: (wanted.y0, wanted.y1), to: max(old.height, limits.maxPixels / wanted.width))
                }
                if wanted.width * wanted.height > limits.maxPixels {
                    (wanted.x0, wanted.x1) = Self.clamp(old: (old.x0, old.x1), wanted: (wanted.x0, wanted.x1), to: max(old.width, limits.maxPixels / wanted.height))
                }
            }
        }
        guard wanted != bounds || buffer == nil else {
            return false
        }
        reallocate(to: wanted)
        return !limited && bounds.contains(needed)
    }

    private func fits(_ bounds: Bounds) -> Bool {
        bounds.width <= limits.maxSide && bounds.height <= limits.maxSide && bounds.width * bounds.height <= limits.maxPixels
    }

    /// `wanted` cut down to `length`, trimming only what it adds to `old`, in proportion on each side, in whole cells.
    static func clamp(old: (Int, Int), wanted: (Int, Int), to length: Int) -> (Int, Int) {
        let cell = Self.cell
        let limit = max(length / cell * cell, old.1 - old.0)
        let extra = (wanted.1 - wanted.0) - limit
        guard extra > 0 else {
            return wanted
        }
        let before = old.0 - wanted.0, after = wanted.1 - old.1
        guard before + after > 0 else {
            return wanted
        }
        var trimBefore = Int((Double(extra) * Double(before) / Double(before + after) / Double(cell)).rounded()) * cell
        trimBefore = min(trimBefore, before)
        let trimAfter = min(extra - trimBefore, after)
        trimBefore = min(before, extra - trimAfter)
        return (wanted.0 + trimBefore, wanted.1 - trimAfter)
    }

    private func reallocate(to new: Bounds) {
        let fresh = UnsafeMutablePointer<UInt8>.allocate(capacity: new.width * new.height * 4)
        fresh.initialize(repeating: 0, count: new.width * new.height * 4)
        let newMipWidth = new.width / Self.cell, newMipHeight = new.height / Self.cell
        var newMip = [UInt8](repeating: 0, count: newMipWidth * newMipHeight * 4)
        if let buffer {
            let shared = bounds.intersection(new)
            if !shared.isEmpty {
                for y in shared.y0..<shared.y1 {
                    let source = buffer + ((y - bounds.y0) * bounds.width + (shared.x0 - bounds.x0)) * 4
                    let destination = fresh + ((y - new.y0) * new.width + (shared.x0 - new.x0)) * 4
                    destination.update(from: source, count: shared.width * 4)
                }
                let cells = Bounds(x0: shared.x0 / Self.cell, y0: shared.y0 / Self.cell, x1: shared.x1 / Self.cell, y1: shared.y1 / Self.cell)
                for cy in cells.y0..<cells.y1 {
                    let source = ((cy - bounds.y0 / Self.cell) * mipWidth + (cells.x0 - bounds.x0 / Self.cell)) * 4
                    let destination = ((cy - new.y0 / Self.cell) * newMipWidth + (cells.x0 - new.x0 / Self.cell)) * 4
                    newMip.replaceSubrange(destination..<destination + cells.width * 4, with: mip[source..<source + cells.width * 4])
                }
            }
            buffer.deallocate()
        }
        buffer = fresh
        bounds = new
        mip = newMip
        mipWidth = newMipWidth
        mipHeight = newMipHeight
    }

    // MARK: Painting

    /// Paints `rect` of the frame, whose top left is at `at` in the world, as content. Returns whether anything landed.
    @discardableResult
    func paintContent(_ frame: UnsafeMutablePointer<UInt8>, width: Int, height: Int, at: (x: Int, y: Int), rect: (x: Int, y: Int, width: Int, height: Int)) -> Bool {
        let world = Bounds(x0: at.x + rect.x, y0: at.y + rect.y, x1: at.x + rect.x + rect.width, y1: at.y + rect.y + rect.height)
        if buffer == nil {
            ensure(world)
        }
        guard let buffer else {
            return false
        }
        let clipped = world.intersection(bounds)
        guard !clipped.isEmpty else {
            return false
        }
        let stride = stride
        for wy in clipped.y0..<clipped.y1 {
            let fy = wy - at.y, fx = clipped.x0 - at.x
            let source = frame + (fy * width + fx) * 4
            let destination = buffer + (wy - bounds.y0) * stride + (clipped.x0 - bounds.x0) * 4
            destination.update(from: source, count: clipped.width * 4)
            var p = destination + 3
            for _ in 0..<clipped.width {
                p.pointee = 255
                p += 4
            }
        }
        painted(clipped)
        return true
    }

    /// Paints `tile` of the frame at `at` in the world as sticky paint, only where no content has been seen.
    @discardableResult
    func paintPinned(_ frame: UnsafeMutablePointer<UInt8>, width: Int, height: Int, tile: (x: Int, y: Int, width: Int, height: Int), at: (x: Int, y: Int), flags: UInt8) -> Bool {
        guard let buffer else {
            return false
        }
        let code = 240 + flags
        let world = Bounds(x0: at.x, y0: at.y, x1: at.x + tile.width, y1: at.y + tile.height)
        let clipped = world.intersection(bounds)
        guard !clipped.isEmpty else {
            return false
        }
        let stride = stride
        var any = false
        for wy in clipped.y0..<clipped.y1 {
            var source = frame + ((tile.y + wy - at.y) * width + tile.x + clipped.x0 - at.x) * 4
            var destination = buffer + (wy - bounds.y0) * stride + (clipped.x0 - bounds.x0) * 4
            for _ in 0..<clipped.width {
                if destination[3] != 255 {
                    destination[0] = source[0]
                    destination[1] = source[1]
                    destination[2] = source[2]
                    destination[3] = code
                    any = true
                }
                source += 4
                destination += 4
            }
        }
        if any {
            pinnedBounds[code] = pinnedBounds[code].map { $0.union(clipped) } ?? clipped
            painted(clipped)
        }
        return any
    }

    /// Turns content paint in `rect` into sticky paint with `flags`, for a tile that turned out to be sticky after it
    /// was painted as content.
    func markPinned(rect: (x: Int, y: Int, width: Int, height: Int), flags: UInt8) {
        guard let buffer else {
            return
        }
        let code = 240 + flags
        let clipped = Bounds(x0: rect.x, y0: rect.y, x1: rect.x + rect.width, y1: rect.y + rect.height).intersection(bounds)
        guard !clipped.isEmpty else {
            return
        }
        for wy in clipped.y0..<clipped.y1 {
            var p = buffer + (wy - bounds.y0) * stride + (clipped.x0 - bounds.x0) * 4 + 3
            for _ in 0..<clipped.width {
                if p.pointee == 255 {
                    p.pointee = code
                }
                p += 4
            }
        }
        pinnedBounds[code] = pinnedBounds[code].map { $0.union(clipped) } ?? clipped
    }

    /// Clears the sticky paint with `flags` in `rect`.
    func clearPinned(rect: (x: Int, y: Int, width: Int, height: Int), flags: UInt8) {
        clear(Bounds(x0: rect.x, y0: rect.y, x1: rect.x + rect.width, y1: rect.y + rect.height), code: 240 + flags)
    }

    /// Clears every sticky paint anchored to any of the edges in `flags`, whose edge has moved.
    func clearPinned(anchoredTo flags: UInt8) {
        for (code, extent) in pinnedBounds where (code - 240) & flags != 0 {
            clear(extent, code: code)
            pinnedBounds[code] = nil
        }
    }

    private func clear(_ rect: Bounds, code: UInt8) {
        guard let buffer else {
            return
        }
        let clipped = rect.intersection(bounds)
        guard !clipped.isEmpty else {
            return
        }
        for wy in clipped.y0..<clipped.y1 {
            var p = buffer + (wy - bounds.y0) * stride + (clipped.x0 - bounds.x0) * 4
            for _ in 0..<clipped.width {
                if p[3] == code {
                    p[0] = 0
                    p[1] = 0
                    p[2] = 0
                    p[3] = 0
                }
                p += 4
            }
        }
        updateMip(clipped)
    }

    /// Paints pixels `x0..<x1` of the frame's row `y` as content, with the frame's top left at `at` in the world.
    /// Returns what landed; `painted` must be told once the rows are done.
    func paintContentRow(_ frame: UnsafeMutablePointer<UInt8>, width: Int, y: Int, x0: Int, x1: Int, at: (x: Int, y: Int)) -> Bounds? {
        let world = Bounds(x0: at.x + x0, y0: at.y + y, x1: at.x + x1, y1: at.y + y + 1)
        guard let buffer else {
            return nil
        }
        let clipped = world.intersection(bounds)
        guard !clipped.isEmpty else {
            return nil
        }
        let source = frame + (y * width + clipped.x0 - at.x) * 4
        let destination = buffer + (clipped.y0 - bounds.y0) * stride + (clipped.x0 - bounds.x0) * 4
        destination.update(from: source, count: clipped.width * 4)
        var p = destination + 3
        for _ in 0..<clipped.width {
            p.pointee = 255
            p += 4
        }
        return clipped
    }

    /// Paints pixels `x0..<x1` of the frame's row `y` as sticky paint with `flags`, only where no content has been
    /// seen. Returns what landed; `painted` must be told once the rows are done.
    func paintPinnedRow(_ frame: UnsafeMutablePointer<UInt8>, width: Int, y: Int, x0: Int, x1: Int, at: (x: Int, y: Int), flags: UInt8) -> Bounds? {
        let code = 240 + flags
        let world = Bounds(x0: at.x + x0, y0: at.y + y, x1: at.x + x1, y1: at.y + y + 1)
        guard let buffer else {
            return nil
        }
        let clipped = world.intersection(bounds)
        guard !clipped.isEmpty else {
            return nil
        }
        var source = frame + (y * width + clipped.x0 - at.x) * 4
        var destination = buffer + (clipped.y0 - bounds.y0) * stride + (clipped.x0 - bounds.x0) * 4
        var any = false
        for _ in 0..<clipped.width {
            if destination[3] != 255 {
                destination[0] = source[0]
                destination[1] = source[1]
                destination[2] = source[2]
                destination[3] = code
                any = true
            }
            source += 4
            destination += 4
        }
        guard any else {
            return nil
        }
        pinnedBounds[code] = pinnedBounds[code].map { $0.union(clipped) } ?? clipped
        return clipped
    }

    /// Notes that `rect` was painted: the image grows to hold it and the preview is brought up to date, except
    /// inside `skip`, where the preview is left as it was.
    func painted(_ rect: Bounds, refreshingOutside skip: Bounds? = nil) {
        seen = seen.map { $0.union(rect) } ?? rect
        guard let skip, !rect.intersection(skip).isEmpty else {
            updateMip(rect)
            return
        }
        // The strips of `rect` above, below, left and right of `skip`.
        if rect.y0 < skip.y0 { updateMip(Bounds(x0: rect.x0, y0: rect.y0, x1: rect.x1, y1: min(rect.y1, skip.y0))) }
        if rect.y1 > skip.y1 { updateMip(Bounds(x0: rect.x0, y0: max(rect.y0, skip.y1), x1: rect.x1, y1: rect.y1)) }
        let y0 = max(rect.y0, skip.y0), y1 = min(rect.y1, skip.y1)
        if rect.x0 < skip.x0 { updateMip(Bounds(x0: rect.x0, y0: y0, x1: min(rect.x1, skip.x0), y1: y1)) }
        if rect.x1 > skip.x1 { updateMip(Bounds(x0: max(rect.x0, skip.x1), y0: y0, x1: rect.x1, y1: y1)) }
    }

    /// Recomputes the preview cells under `rect`: the mean colour, premultiplied by how much of the cell is painted.
    private func updateMip(_ rect: Bounds) {
        guard let buffer else {
            return
        }
        let cell = Self.cell
        let cx0 = (rect.x0 - bounds.x0) / cell, cx1 = (rect.x1 - bounds.x0 + cell - 1) / cell
        let cy0 = (rect.y0 - bounds.y0) / cell, cy1 = (rect.y1 - bounds.y0 + cell - 1) / cell
        let stride = stride
        mip.withUnsafeMutableBufferPointer { mip in
            for cy in cy0..<min(cy1, mipHeight) {
                for cx in cx0..<min(cx1, mipWidth) {
                    var r = 0, g = 0, b = 0, a = 0
                    for y in 0..<cell {
                        var p = buffer + (cy * cell + y) * stride + cx * cell * 4
                        for _ in 0..<cell {
                            if p[3] != 0 {
                                r += Int(p[0])
                                g += Int(p[1])
                                b += Int(p[2])
                                a += 1
                            }
                            p += 4
                        }
                    }
                    let i = (cy * mipWidth + cx) * 4
                    let n = cell * cell
                    mip[i] = UInt8(r / n)
                    mip[i + 1] = UInt8(g / n)
                    mip[i + 2] = UInt8(b / n)
                    mip[i + 3] = UInt8(a * 255 / n)
                }
            }
        }
    }

    // MARK: Reading

    /// The mean absolute difference between every other pixel of `tile` in the frame and the canvas where the tile
    /// would land with the frame at `at`; NaN when too little of that is painted to say.
    func residual(of frame: UnsafeMutablePointer<UInt8>, width: Int, height: Int, tile: (x: Int, y: Int, width: Int, height: Int), at: (x: Int, y: Int)) -> Float {
        guard let buffer else {
            return .nan
        }
        let world = Bounds(x0: at.x + tile.x, y0: at.y + tile.y, x1: at.x + tile.x + tile.width, y1: at.y + tile.y + tile.height)
        let clipped = world.intersection(bounds)
        guard !clipped.isEmpty else {
            return .nan
        }
        var sum = 0
        var n = 0
        let stride = stride
        var wy = clipped.y0
        while wy < clipped.y1 {
            var source = frame + ((wy - at.y) * width + clipped.x0 - at.x) * 4
            var p = buffer + (wy - bounds.y0) * stride + (clipped.x0 - bounds.x0) * 4
            var wx = clipped.x0
            while wx < clipped.x1 {
                if p[3] != 0 {
                    sum += abs(Int(source[0]) - Int(p[0])) + abs(Int(source[1]) - Int(p[1])) + abs(Int(source[2]) - Int(p[2]))
                    n += 1
                }
                source += 16
                p += 16
                wx += 4
            }
            wy += 2
        }
        guard n >= 6 else {
            return .nan
        }
        return Float(sum) / Float(3 * n)
    }

    private static func bitmapInfo(_ byteOrder: ScrollStitcher.ByteOrder) -> CGBitmapInfo {
        switch byteOrder {
        case .bgra: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        case .rgba: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
    }

    private static func makeImage(_ data: Data, width: Int, height: Int, byteOrder: ScrollStitcher.ByteOrder, colorSpace: CGColorSpace) -> CGImage? {
        guard width > 0, height > 0, let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo(byteOrder), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The painted part of the canvas at an eighth of its size, clear where nothing is painted.
    func previewImage(byteOrder: ScrollStitcher.ByteOrder) -> CGImage? {
        guard let seen, buffer != nil else {
            return nil
        }
        let cell = Self.cell
        let cx0 = (seen.x0 - bounds.x0) / cell, cx1 = min(mipWidth, (seen.x1 - bounds.x0 + cell - 1) / cell)
        let cy0 = (seen.y0 - bounds.y0) / cell, cy1 = min(mipHeight, (seen.y1 - bounds.y0 + cell - 1) / cell)
        let width = cx1 - cx0, height = cy1 - cy0
        guard width > 0, height > 0 else {
            return nil
        }
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { out in
            mip.withUnsafeBytes { mip in
                for cy in 0..<height {
                    let source = ((cy + cy0) * mipWidth + cx0) * 4
                    out.baseAddress!.advanced(by: cy * width * 4).copyMemory(from: mip.baseAddress!.advanced(by: source), byteCount: width * 4)
                }
            }
        }
        return Self.makeImage(data, width: width, height: height, byteOrder: byteOrder, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    /// Who painted each pixel of the seen part, as greys: black for nobody, white for content, grey for sticky paint.
    func ownerImage() -> CGImage? {
        guard let seen, let buffer else {
            return nil
        }
        let region = seen.intersection(bounds)
        var data = Data(count: region.width * region.height * 4)
        let stride = stride
        data.withUnsafeMutableBytes { out in
            let base = out.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<region.height {
                var p = buffer + (region.y0 + y - bounds.y0) * stride + (region.x0 - bounds.x0) * 4 + 3
                var q = base + y * region.width * 4
                for _ in 0..<region.width {
                    let code = p.pointee
                    if code == 0 || code == 255 {
                        q[0] = code
                        q[1] = code
                        q[2] = code
                    } else {
                        // Red for top, yellow for bottom, green for left, blue for right; mixed for corners.
                        let flags = code - 240
                        q[0] = flags & 3 != 0 ? 220 : 40
                        q[1] = flags & 2 != 0 || flags & 4 != 0 ? 200 : 40
                        q[2] = flags & 8 != 0 ? 220 : 40
                    }
                    q[3] = 255
                    p += 4
                    q += 4
                }
            }
        }
        return Self.makeImage(data, width: region.width, height: region.height, byteOrder: .rgba, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    /// Every pixel seen, opaque, with the rest clear.
    func image(byteOrder: ScrollStitcher.ByteOrder, colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CGImage? {
        guard let seen, let buffer else {
            return nil
        }
        let region = seen.intersection(bounds)
        guard !region.isEmpty else {
            return nil
        }
        var data = Data(count: region.width * region.height * 4)
        let stride = stride
        data.withUnsafeMutableBytes { out in
            let base = out.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<region.height {
                let source = buffer + (region.y0 + y - bounds.y0) * stride + (region.x0 - bounds.x0) * 4
                let destination = base + y * region.width * 4
                destination.update(from: source, count: region.width * 4)
                var p = destination + 3
                for _ in 0..<region.width {
                    if p.pointee != 0 {
                        p.pointee = 255
                    }
                    p += 4
                }
            }
        }
        return Self.makeImage(data, width: region.width, height: region.height, byteOrder: byteOrder, colorSpace: colorSpace)
    }
}
