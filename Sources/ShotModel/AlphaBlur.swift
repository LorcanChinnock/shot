import Foundation

/// A gaussian blur of 8-bit levels, approximated by three box blurs per axis, for a shadow drawn where there's no blur
/// filter. Levels past the edge count as 0, as a shadow's surroundings are clear. CoreGraphics' shadow of blur `b` is
/// close to a gaussian of `sigma` `b / 2`.
public enum AlphaBlur {
    /// The widths of the three boxes whose blur is closest to a gaussian of `sigma`, each odd, so each is centred.
    public static func boxWidths(sigma: CGFloat) -> [Int] {
        let passes = 3
        guard sigma > 0 else {
            return Array(repeating: 1, count: passes)
        }
        let variance = 12 * sigma * sigma
        var lower = Int(sqrt(variance / CGFloat(passes) + 1))
        if lower % 2 == 0 {
            lower -= 1
        }
        let l = CGFloat(lower)
        // How many passes use the lower width so the variances sum to sigma's.
        let narrow = Int(((variance - CGFloat(passes) * l * l - 4 * CGFloat(passes) * l - 3 * CGFloat(passes)) / (-4 * l - 4)).rounded())
        return (0..<passes).map { $0 < narrow ? lower : lower + 2 }
    }

    /// How far the blur of `sigma` spreads a level, in whole pixels.
    public static func reach(sigma: CGFloat) -> Int {
        boxWidths(sigma: sigma).reduce(0) { $0 + ($1 - 1) / 2 }
    }

    /// Blurs the `width` by `height` levels in `levels`, each row `stride` bytes apart, in place.
    public static func blur(_ levels: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int, stride: Int, sigma: CGFloat) {
        let widths = boxWidths(sigma: sigma)
        guard width > 0, height > 0, widths.contains(where: { $0 > 1 }) else {
            return
        }
        var line = [UInt8](repeating: 0, count: max(width, height))
        for box in widths where box > 1 {
            for y in 0..<height {
                blurLine(levels, start: y * stride, step: 1, count: width, box: box, scratch: &line)
            }
            for x in 0..<width {
                blurLine(levels, start: x, step: stride, count: height, box: box, scratch: &line)
            }
        }
    }

    /// One box blur along `count` levels from `start`, `step` apart.
    private static func blurLine(_ levels: UnsafeMutableBufferPointer<UInt8>, start: Int, step: Int, count: Int, box: Int, scratch: inout [UInt8]) {
        let radius = box / 2
        for i in 0..<count {
            scratch[i] = levels[start + i * step]
        }
        // The running sum of the window centred on `i`.
        var sum = 0
        for i in 0..<min(radius, count) {
            sum += Int(scratch[i])
        }
        for i in 0..<count {
            if i + radius < count {
                sum += Int(scratch[i + radius])
            }
            if i - radius - 1 >= 0 {
                sum -= Int(scratch[i - radius - 1])
            }
            levels[start + i * step] = UInt8((sum * 2 + box) / (box * 2))
        }
    }
}
