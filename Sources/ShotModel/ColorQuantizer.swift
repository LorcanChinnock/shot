import Foundation

/// Reduces a GIF frame's pixels to at most 256 colors by median cut. Colors go into a histogram of 5 bits per channel;
/// the box of colors with the most pixels across the widest range splits at its median, again and again until there
/// are enough boxes, and each box's color is the mean of the pixels in it. Pixels less than half opaque take the
/// transparent index. There's no dithering, so flat areas stay flat and compress well.
public enum ColorQuantizer {
    public struct Frame: Equatable, Sendable {
        /// Red, green and blue bytes for each color.
        public var palette: [UInt8]
        /// An index into `palette`, or `transparentIndex`, for each pixel.
        public var indices: [UInt8]
        /// The index of the transparent pixels, one past the last color; `nil` when no pixel is transparent.
        public var transparentIndex: UInt8?

        public var colorCount: Int { palette.count / 3 }
    }

    private static let bins = 1 << 15

    /// `pixels` holds premultiplied red, green, blue and alpha bytes in that order in memory, as `Bitmap` lays them out.
    public static func quantize(_ pixels: [UInt32], maxColors: Int = 256) -> Frame {
        precondition((2...256).contains(maxColors))
        var population = [Int](repeating: 0, count: bins)
        var sums = [Int](repeating: 0, count: bins * 3)
        var transparent = false
        pixels.withUnsafeBufferPointer { pixels in
            for pixel in pixels {
                guard let (r, g, b) = color(pixel) else {
                    transparent = true
                    continue
                }
                let bin = bin(r, g, b)
                population[bin] += 1
                sums[bin * 3] += r
                sums[bin * 3 + 1] += g
                sums[bin * 3 + 2] += b
            }
        }

        var occupied = (0..<bins).filter { population[$0] > 0 }
        var boxes = occupied.isEmpty ? [] : [Box(occupied.indices, occupied, population)]
        let colors = maxColors - (transparent ? 1 : 0)
        while boxes.count < colors, let index = boxes.indices.filter({ boxes[$0].range.count > 1 }).max(by: { boxes[$0].score < boxes[$1].score }) {
            let box = boxes[index]
            let axis = box.widestAxis
            occupied[box.range].sort { channel(of: $0, axis) < channel(of: $1, axis) }
            // Cut where half the box's pixels lie on each side, keeping at least one bin in each half.
            var seen = 0, cut = box.range.lowerBound
            for position in box.range.dropLast() {
                seen += population[occupied[position]]
                cut = position + 1
                if seen * 2 >= box.population { break }
            }
            boxes[index] = Box(box.range.lowerBound..<cut, occupied, population)
            boxes.append(Box(cut..<box.range.upperBound, occupied, population))
        }

        var palette: [UInt8] = []
        var lookup = [UInt8](repeating: 0, count: bins)
        for (index, box) in boxes.enumerated() {
            var total = (r: 0, g: 0, b: 0)
            for bin in occupied[box.range] {
                total.r += sums[bin * 3]
                total.g += sums[bin * 3 + 1]
                total.b += sums[bin * 3 + 2]
                lookup[bin] = UInt8(index)
            }
            let half = box.population / 2
            palette += [UInt8((total.r + half) / box.population), UInt8((total.g + half) / box.population), UInt8((total.b + half) / box.population)]
        }

        let transparentIndex = transparent ? UInt8(boxes.count) : nil
        let indices = pixels.map { pixel in
            color(pixel).map { lookup[bin($0.r, $0.g, $0.b)] } ?? transparentIndex ?? 0
        }
        return Frame(palette: palette, indices: indices, transparentIndex: transparentIndex)
    }

    /// The straight color of a premultiplied pixel, or `nil` when it's less than half opaque.
    static func color(_ pixel: UInt32) -> (r: Int, g: Int, b: Int)? {
        let pixel = UInt32(littleEndian: pixel)
        let alpha = Int(pixel >> 24)
        guard alpha >= 128 else { return nil }
        let r = Int(pixel & 0xFF), g = Int(pixel >> 8 & 0xFF), b = Int(pixel >> 16 & 0xFF)
        guard alpha < 255 else { return (r, g, b) }
        func straight(_ value: Int) -> Int { min(255, (value * 255 + alpha / 2) / alpha) }
        return (straight(r), straight(g), straight(b))
    }

    private static func bin(_ r: Int, _ g: Int, _ b: Int) -> Int {
        (r >> 3) << 10 | (g >> 3) << 5 | b >> 3
    }

    /// Red, green or blue, 0 to 2, of a bin, 0 to 31.
    private static func channel(of bin: Int, _ axis: Int) -> Int {
        bin >> (10 - axis * 5) & 31
    }

    private struct Box {
        /// The bins, as positions in the occupied bins.
        var range: Range<Int>
        var population = 0
        var widestAxis = 0
        var width = 0

        init(_ range: Range<Int>, _ occupied: [Int], _ population: [Int]) {
            self.range = range
            var low = [31, 31, 31], high = [0, 0, 0]
            for bin in occupied[range] {
                self.population += population[bin]
                for axis in 0..<3 {
                    low[axis] = min(low[axis], channel(of: bin, axis))
                    high[axis] = max(high[axis], channel(of: bin, axis))
                }
            }
            for axis in 0..<3 where high[axis] - low[axis] > width {
                width = high[axis] - low[axis]
                widestAxis = axis
            }
        }

        /// Which box splits next: the one whose pixels spread furthest, weighted by how many there are.
        var score: Int { population * width }
    }
}
