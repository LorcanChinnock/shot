import Foundation

// The filters `ImageEffects` asks for, on plain pixels, for where there's no Core Image. Each is made to match what
// Core Image draws on a Mac (`CoreImageEffects`), so a redaction hides as much on Linux as on a Mac. Regions are in
// pixels with the origin at the bottom left, as Core Image has them, and pixels past an image's edge repeat the nearest
// edge pixel.

extension Bitmap {
    /// A gaussian blur of `radius` pixels, Core Image's radius being the gaussian's standard deviation. It blurs in
    /// linear light, as Core Image does, so a light edge doesn't darken where it meets a dark one.
    public func blurred(radius: CGFloat) -> Bitmap {
        guard radius > 0 else {
            return self
        }
        let count = width * height
        // A capture is usually opaque, and its alpha stays so, which saves blurring it and converting by it.
        let opaque = !BitmapImage(self).hasTransparentPixels
        var alpha = [Float](repeating: 1, count: count)
        var plane = [Float](repeating: 0, count: count)
        var out = [UInt8](repeating: 255, count: count * 4)
        pixels.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            out.withUnsafeMutableBufferPointer { out in
                alpha.withUnsafeMutableBufferPointer { alpha in
                    plane.withUnsafeMutableBufferPointer { plane in
                        if !opaque {
                            for i in 0..<count {
                                alpha[i] = Float(source[i * 4 + 3]) / 255
                            }
                            PlaneBlur.blur(alpha, width: width, height: height, sigma: radius)
                            for i in 0..<count {
                                out[i * 4 + 3] = SRGB.byte(alpha[i])
                            }
                        }
                        for channel in 0..<3 {
                            SRGB.toLinear(source, channel: channel, opaque: opaque, into: plane)
                            PlaneBlur.blur(plane, width: width, height: height, sigma: radius)
                            SRGB.toEncoded(plane, alpha: opaque ? nil : UnsafeBufferPointer(alpha), channel: channel, into: out)
                        }
                    }
                }
            }
        }
        return Bitmap(width: width, height: height, scale: scale, pixels: Data(out))!
    }

    /// A greyscale mask, its level in red, green and blue, given a gaussian blur of `radius` pixels. Its levels are
    /// blurred as plain coverage values, without converting them to linear light. The blurred mask is opaque.
    public func blurredMask(radius: CGFloat) -> Bitmap {
        let count = width * height
        var plane = [Float](repeating: 0, count: count)
        pixels.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            for i in 0..<count {
                plane[i] = Float(source[i * 4]) / 255
            }
        }
        plane.withUnsafeMutableBufferPointer { PlaneBlur.blur($0, width: width, height: height, sigma: radius) }
        return Bitmap.grey(width: width, height: height, scale: scale) { plane[$0] }
    }

    /// The shape of the pixels that aren't clear grown by `radius` pixels, white on black: each level is the most alpha
    /// within a disc of `radius` rounded down, as Core Image's morphology maximum takes it. It reaches `radius` rounded up
    /// past each edge, so the mask is that much bigger on every side.
    public func grownMask(radius: CGFloat) -> Bitmap {
        let reach = Int(radius.rounded(.up)), disc = Int(radius.rounded(.down))
        let grownWidth = width + 2 * reach, grownHeight = height + 2 * reach
        // A row of alpha in the grown mask's columns, clear past the image.
        var alphaRows = [[UInt8]](repeating: [UInt8](repeating: 0, count: grownWidth), count: height)
        pixels.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            for y in 0..<height {
                for x in 0..<width {
                    alphaRows[y][reach + x] = source[y * bytesPerRow + x * 4 + 3]
                }
            }
        }
        // For each of the disc's rows above or below its centre, how far it reaches left and right.
        let halfWidths = (-disc...disc).map { dy in Int(Double(disc * disc - dy * dy).squareRoot()) }
        var levels = [UInt8](repeating: 0, count: grownWidth * grownHeight)
        var widened = [UInt8](repeating: 0, count: grownWidth)
        for y in 0..<grownHeight {
            for (index, half) in halfWidths.enumerated() {
                let row = y - reach + index - disc
                guard row >= 0, row < height else {
                    continue
                }
                RunningMax.widen(alphaRows[row], by: half, into: &widened)
                for x in 0..<grownWidth where widened[x] > levels[y * grownWidth + x] {
                    levels[y * grownWidth + x] = widened[x]
                }
            }
        }
        return Bitmap.grey(width: grownWidth, height: grownHeight, scale: scale) { Float(levels[$0]) / 255 }
    }

    /// `region` in square blocks `blockSize` pixels wide, lined up with the region's origin, each the colour at its middle
    /// as Core Image's pixellate takes it: the four pixels nearest the middle, weighted by how near. A pixel belongs to the
    /// block its centre is in. `nil` when the region holds no whole pixel.
    public func pixelated(region: CGRect, blockSize: CGFloat) -> Bitmap? {
        let region = region.integral
        guard region.width >= 1, region.height >= 1 else {
            return nil
        }
        return blocks(over: region, origin: region.origin, size: blockSize)
    }

    /// `region` in blocks `radius` pixels wide, lined up with the region's origin, as `pixelated` makes them, then given
    /// a gaussian blur of `radius`, which reaches across the region's edge into the blocks beyond it. `nil` when the
    /// region holds no whole pixel.
    public func blurredBlocks(region: CGRect, radius: CGFloat) -> Bitmap? {
        let region = region.integral
        guard region.width >= 1, region.height >= 1 else {
            return nil
        }
        // The blocks as far past the region as the blur reaches, so its edge blurs into them.
        let reach = CGFloat(PlaneBlur.reach(sigma: radius))
        let blocks = blocks(over: region.insetBy(dx: -reach, dy: -reach), origin: region.origin, size: radius).blurred(radius: radius)
        return BitmapImage(blocks).cropping(to: CGRect(x: reach, y: reach, width: region.width, height: region.height))?.bitmap
    }

    /// The pixels of `area`, a whole number of pixels with the origin at the bottom left, each the colour at the middle of
    /// the block `size` pixels wide it falls in, the blocks lined up with `origin`.
    private func blocks(over area: CGRect, origin: CGPoint, size: CGFloat) -> Bitmap {
        let size = Double(max(size, 1))
        let areaX = Int(area.minX), areaY = Int(area.minY), areaWidth = Int(area.width), areaHeight = Int(area.height)
        let originX = Double(origin.x), originY = Double(origin.y)
        /// The block a pixel's centre is in, along one axis.
        func block(_ pixel: Int, _ origin: Double) -> Int { Int(((Double(pixel) + 0.5 - origin) / size).rounded(.down)) }
        /// The first pixel of `block`, along one axis.
        func start(_ block: Int, _ origin: Double) -> Int { Int((Double(block) * size + origin - 0.5).rounded(.up)) }
        var out = [UInt8](repeating: 0, count: areaWidth * areaHeight * 4)
        pixels.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            for blockY in block(areaY, originY)...block(areaY + areaHeight - 1, originY) {
                let bottom = start(blockY, originY), top = start(blockY + 1, originY)
                for blockX in block(areaX, originX)...block(areaX + areaWidth - 1, originX) {
                    let left = start(blockX, originX), right = start(blockX + 1, originX)
                    // Core Image's sample of the block's middle: the four pixels around it, weighted by how near each is.
                    let middleX = originX + (Double(blockX) + 0.5) * size - 0.5, middleY = originY + (Double(blockY) + 0.5) * size - 0.5
                    let x0 = Int(middleX.rounded(.down)), y0 = Int(middleY.rounded(.down))
                    let fx = middleX - Double(x0), fy = middleY - Double(y0)
                    var sample = [0.0, 0.0, 0.0, 0.0]
                    for (y, wy) in [(y0, 1 - fy), (y0 + 1, fy)] where wy > 0 {
                        // Rows count down from the top, and past the edge they repeat the edge row.
                        let row = (height - 1 - min(max(y, 0), height - 1)) * bytesPerRow
                        for (x, wx) in [(x0, 1 - fx), (x0 + 1, fx)] where wx > 0 {
                            let i = row + min(max(x, 0), width - 1) * 4
                            for channel in 0..<4 {
                                sample[channel] += wx * wy * Double(source[i + channel])
                            }
                        }
                    }
                    let colour: [UInt8] = sample.map { UInt8(min($0.rounded(), 255)) }
                    for y in max(bottom, areaY)..<min(top, areaY + areaHeight) {
                        let row = (areaY + areaHeight - 1 - y) * areaWidth
                        for x in max(left, areaX)..<min(right, areaX + areaWidth) {
                            let o = (row + x - areaX) * 4
                            (out[o], out[o + 1], out[o + 2], out[o + 3]) = (colour[0], colour[1], colour[2], colour[3])
                        }
                    }
                }
            }
        }
        return Bitmap(width: areaWidth, height: areaHeight, scale: scale, pixels: Data(out))!
    }

    /// An opaque greyscale bitmap, each pixel's level, 0 to 1, from `level(index)`.
    private static func grey(width: Int, height: Int, scale: CGFloat, level: (Int) -> Float) -> Bitmap {
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<width * height {
            let byte = SRGB.byte(level(i))
            (out[i * 4], out[i * 4 + 1], out[i * 4 + 2]) = (byte, byte, byte)
        }
        return Bitmap(width: width, height: height, scale: scale, pixels: Data(out))!
    }
}

/// A gaussian blur of a plane of values, with the edges clamped. Below `boxesFrom` it's the gaussian itself, since three
/// boxes only a few pixels wide are too coarse to look like one; above it, three box blurs, which cost the same however
/// wide the blur is.
private enum PlaneBlur {
    static let boxesFrom: CGFloat = 3

    /// How far the blur of `sigma` spreads a value, in whole pixels.
    static func reach(sigma: CGFloat) -> Int {
        sigma < boxesFrom ? Int((3 * sigma).rounded(.up)) : AlphaBlur.reach(sigma: sigma)
    }

    static func blur(_ plane: UnsafeMutableBufferPointer<Float>, width: Int, height: Int, sigma: CGFloat) {
        guard sigma > 0, let plane = plane.baseAddress else {
            return
        }
        guard sigma >= boxesFrom else {
            let kernel = kernel(sigma: sigma)
            let scratch = UnsafeMutablePointer<Float>.allocate(capacity: width * height)
            defer { scratch.deallocate() }
            kernel.withUnsafeBufferPointer { kernel in
                convolveRows(plane, width: width, height: height, kernel: kernel, scratch: scratch)
                convolveColumns(plane, width: width, height: height, kernel: kernel, scratch: scratch)
            }
            return
        }
        // Each box clamps at the edge of what it blurs, but the gaussian blurs the edge values repeated without end. So the
        // boxes blur the plane with its edges repeated as far as they reach, where the two are the same.
        let pad = AlphaBlur.reach(sigma: sigma), paddedWidth = width + 2 * pad, paddedHeight = height + 2 * pad
        let padded = UnsafeMutablePointer<Float>.allocate(capacity: paddedWidth * paddedHeight)
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: paddedWidth * paddedHeight)
        defer {
            padded.deallocate()
            scratch.deallocate()
        }
        for y in 0..<paddedHeight {
            let source = plane + (y < pad ? 0 : y - pad < height ? y - pad : height - 1) * width
            let row = padded + y * paddedWidth
            row.update(repeating: source[0], count: pad)
            (row + pad).update(from: source, count: width)
            (row + pad + width).update(repeating: source[width - 1], count: pad)
        }
        for box in AlphaBlur.boxWidths(sigma: sigma) where box > 1 {
            rows(padded, width: paddedWidth, height: paddedHeight, box: box, scratch: scratch)
            columns(padded, width: paddedWidth, height: paddedHeight, box: box, scratch: scratch)
        }
        for y in 0..<height {
            (plane + y * width).update(from: padded + (y + pad) * paddedWidth + pad, count: width)
        }
    }

    /// The gaussian's weights from `-reach` to `reach`, summing to 1.
    private static func kernel(sigma: CGFloat) -> [Float] {
        let reach = reach(sigma: sigma), s = Double(sigma)
        let weights = (-reach...reach).map { exp(-Double($0 * $0) / (2 * s * s)) }
        let total = weights.reduce(0, +)
        return weights.map { Float($0 / total) }
    }

    private static func convolveRows(_ plane: UnsafeMutablePointer<Float>, width: Int, height: Int, kernel: UnsafeBufferPointer<Float>, scratch: UnsafeMutablePointer<Float>) {
        let reach = kernel.count / 2
        scratch.update(from: plane, count: width * height)
        for y in 0..<height {
            let source = scratch + y * width, row = plane + y * width
            for x in 0..<width {
                var sum: Float = 0
                for i in 0..<kernel.count {
                    let at = x + i - reach
                    sum += kernel[i] * source[at < 0 ? 0 : at < width ? at : width - 1]
                }
                row[x] = sum
            }
        }
    }

    /// A row at a time, so it reads memory in order.
    private static func convolveColumns(_ plane: UnsafeMutablePointer<Float>, width: Int, height: Int, kernel: UnsafeBufferPointer<Float>, scratch: UnsafeMutablePointer<Float>) {
        let reach = kernel.count / 2
        scratch.update(from: plane, count: width * height)
        for y in 0..<height {
            let row = plane + y * width
            row.update(repeating: 0, count: width)
            for i in 0..<kernel.count {
                let at = y + i - reach, weight = kernel[i]
                let source = scratch + (at < 0 ? 0 : at < height ? at : height - 1) * width
                for x in 0..<width {
                    row[x] += weight * source[x]
                }
            }
        }
    }

    /// One box blur along each row, in place; `scratch` holds a row.
    private static func rows(_ plane: UnsafeMutablePointer<Float>, width: Int, height: Int, box: Int, scratch: UnsafeMutablePointer<Float>) {
        let radius = box / 2, scale = 1 / Float(box)
        for y in 0..<height {
            let row = plane + y * width
            scratch.update(from: row, count: width)
            // The window centred on 0, the edge value standing in for what's past it.
            var sum = Float(radius + 1) * scratch[0]
            for x in 1...radius {
                sum += scratch[x < width ? x : width - 1]
            }
            for x in 0..<width {
                row[x] = sum * scale
                let entering = x + radius + 1, leaving = x - radius
                sum += scratch[entering < width ? entering : width - 1] - scratch[leaving > 0 ? leaving : 0]
            }
        }
    }

    /// One box blur down each column, in place, a row at a time so it reads memory in order; `scratch` holds the plane.
    private static func columns(_ plane: UnsafeMutablePointer<Float>, width: Int, height: Int, box: Int, scratch: UnsafeMutablePointer<Float>) {
        let radius = box / 2, scale = 1 / Float(box)
        scratch.update(from: plane, count: width * height)
        // Each column's window, centred on row 0.
        let sums = UnsafeMutablePointer<Float>.allocate(capacity: width)
        defer { sums.deallocate() }
        for x in 0..<width {
            sums[x] = Float(radius + 1) * scratch[x]
        }
        for y in 1...radius {
            let row = scratch + (y < height ? y : height - 1) * width
            for x in 0..<width {
                sums[x] += row[x]
            }
        }
        for y in 0..<height {
            let row = plane + y * width
            let entering = scratch + (y + radius + 1 < height ? y + radius + 1 : height - 1) * width
            let leaving = scratch + (y - radius > 0 ? y - radius : 0) * width
            for x in 0..<width {
                row[x] = sums[x] * scale
                sums[x] += entering[x] - leaving[x]
            }
        }
    }
}

/// The most of each run of levels, by van Herk and Gil-Werman's method, which costs the same however wide the run.
private enum RunningMax {
    /// `levels` with each level the most within `half` of it either side, levels past the ends counting as 0.
    static func widen(_ levels: [UInt8], by half: Int, into out: inout [UInt8]) {
        guard half > 0 else {
            out = levels
            return
        }
        let count = levels.count, window = 2 * half + 1
        // Padded with `half` zeros each side, so every window lies within it.
        let padded = [UInt8](repeating: 0, count: half) + levels + [UInt8](repeating: 0, count: half)
        // The most so far from the start of each window-wide block, and to its end.
        var fromStart = padded, toEnd = padded
        for i in 1..<padded.count where i % window != 0 {
            fromStart[i] = max(fromStart[i], fromStart[i - 1])
        }
        for i in stride(from: padded.count - 2, through: 0, by: -1) where (i + 1) % window != 0 {
            toEnd[i] = max(toEnd[i], toEnd[i + 1])
        }
        // The window of level `i` is padded `i...i + 2 * half`, which spans at most two blocks.
        for i in 0..<count {
            out[i] = max(toEnd[i], fromStart[i + 2 * half])
        }
    }
}

/// sRGB's transfer curve, for blurring in linear light.
private enum SRGB {
    /// Each byte as linear light, 0 to 1.
    private static let linear: [Float] = (0...255).map { byte in
        let c = Double(byte) / 255
        return Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
    }

    /// Linear light, in 65535ths, as an sRGB level 0 to 255: fine enough steps to round right where the curve is
    /// steep, near black.
    private static let encoded: [Float] = (0...65535).map { step in
        let l = Double(step) / 65535
        return Float(255 * (l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055))
    }

    /// One channel of premultiplied RGBA `pixels`, as premultiplied linear light.
    static func toLinear(_ pixels: UnsafeRawBufferPointer, channel: Int, opaque: Bool, into plane: UnsafeMutableBufferPointer<Float>) {
        linear.withUnsafeBufferPointer { linear in
            for i in 0..<plane.count {
                let level = Int(pixels[i * 4 + channel])
                guard !opaque else {
                    plane[i] = linear[level]
                    continue
                }
                let alpha = Int(pixels[i * 4 + 3])
                switch alpha {
                case 0: plane[i] = 0
                case 255: plane[i] = linear[level]
                default: plane[i] = linear[min(255, (level * 255 + alpha / 2) / alpha)] * Float(alpha) / 255
                }
            }
        }
    }

    /// Premultiplied linear light as one channel of premultiplied RGBA `pixels`, each with `alpha` 0 to 1, or opaque if
    /// there's none.
    static func toEncoded(_ plane: UnsafeMutableBufferPointer<Float>, alpha: UnsafeBufferPointer<Float>?, channel: Int, into pixels: UnsafeMutableBufferPointer<UInt8>) {
        encoded.withUnsafeBufferPointer { encoded in
            for i in 0..<plane.count {
                let a = alpha?[i] ?? 1
                guard a > 0.5 / 255 else {
                    pixels[i * 4 + channel] = 0
                    continue
                }
                let straight = a == 1 ? plane[i] : plane[i] / a
                let level = encoded[Int((straight < 0 ? 0 : straight > 1 ? 1 : straight) * 65535 + 0.5)]
                pixels[i * 4 + channel] = UInt8(level * (a < 1 ? a : 1) + 0.5)
            }
        }
    }

    /// 0 to 1 as a byte, rounded.
    static func byte(_ value: Float) -> UInt8 {
        UInt8(min(max(value * 255 + 0.5, 0), 255))
    }
}
