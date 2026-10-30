import Accelerate
import Foundation

/// Finds how far one grey image moved to become another, by phase correlation: the peaks of the cross-power
/// spectrum's inverse transform mark the likely translations, however big they are, so a fast flick is found as
/// readily as a slow scroll. The caller checks each peak against the pixels, since a repeating pattern peaks at
/// every period and a sticky header peaks at zero.
final class PhaseCorrelator {
    /// A translation of the view over the content: the new image at `p` shows what the old one showed at `p + v`.
    struct Peak: Equatable {
        var dx: Int
        var dy: Int
        var strength: Float
    }

    let width: Int
    let height: Int
    private let columns: Int
    private let rows: Int
    private let log2Columns: vDSP_Length
    private let log2Rows: vDSP_Length
    private let setup: FFTSetup
    private var aReal: [Float]
    private var aImaginary: [Float]
    private var bReal: [Float]
    private var bImaginary: [Float]
    private let window: [Float]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        var log2W: vDSP_Length = 1, log2H: vDSP_Length = 1
        while 1 << log2W < width { log2W += 1 }
        while 1 << log2H < height { log2H += 1 }
        log2Columns = log2W
        log2Rows = log2H
        columns = 1 << log2W
        rows = 1 << log2H
        setup = vDSP_create_fftsetup(max(log2W, log2H), FFTRadix(kFFTRadix2))!
        let count = columns * rows
        aReal = [Float](repeating: 0, count: count)
        aImaginary = [Float](repeating: 0, count: count)
        bReal = [Float](repeating: 0, count: count)
        bImaginary = [Float](repeating: 0, count: count)
        // A Tukey window: flat over the middle three quarters, so a big scroll's overlap along one edge still counts,
        // and tapered at the edges, so the image's hard border doesn't correlate with itself.
        func taper(_ i: Int, _ n: Int) -> Float {
            let edge = max(1, n / 8)
            if i < edge {
                return 0.5 - 0.5 * cos(.pi * Float(i) / Float(edge))
            }
            if i >= n - edge {
                return 0.5 - 0.5 * cos(.pi * Float(n - 1 - i) / Float(edge))
            }
            return 1
        }
        let horizontal = (0..<width).map { taper($0, width) }
        let vertical = (0..<height).map { taper($0, height) }
        var window = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                window[y * width + x] = horizontal[x] * vertical[y]
            }
        }
        self.window = window
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// The `count` strongest translations from `old` to `new`, both `width` × `height` greys, strongest first.
    /// Each peak is given twice when the transform can't tell a move from its wrap-around, so the caller can try both.
    func peaks(from old: [Float], to new: [Float], count: Int) -> [Peak] {
        load(old, into: &aReal, &aImaginary)
        load(new, into: &bReal, &bImaginary)
        transform(&aReal, &aImaginary, direction: FFTDirection(FFT_FORWARD))
        transform(&bReal, &bImaginary, direction: FFTDirection(FFT_FORWARD))
        // The cross-power spectrum, new × conj(old), normalised to unit magnitude so only the phase, which holds the
        // shift, is left.
        let total = columns * rows
        aReal.withUnsafeMutableBufferPointer { ar in
            aImaginary.withUnsafeMutableBufferPointer { ai in
                bReal.withUnsafeBufferPointer { br in
                    bImaginary.withUnsafeBufferPointer { bi in
                        for i in 0..<total {
                            let re = br[i] * ar[i] + bi[i] * ai[i]
                            let im = bi[i] * ar[i] - br[i] * ai[i]
                            let magnitude = (re * re + im * im).squareRoot() + 1e-6
                            ar[i] = re / magnitude
                            ai[i] = im / magnitude
                        }
                    }
                }
            }
        }
        transform(&aReal, &aImaginary, direction: FFTDirection(FFT_INVERSE))
        return findPeaks(in: aReal, count: count)
    }

    private func load(_ image: [Float], into real: inout [Float], _ imaginary: inout [Float]) {
        var mean: Float = 0
        image.withUnsafeBufferPointer { vDSP_meanv($0.baseAddress!, 1, &mean, vDSP_Length(width * height)) }
        for i in 0..<(columns * rows) {
            real[i] = 0
            imaginary[i] = 0
        }
        for y in 0..<height {
            let source = y * width
            let destination = y * columns
            for x in 0..<width {
                real[destination + x] = (image[source + x] - mean) * window[source + x]
            }
        }
    }

    private func transform(_ real: inout [Float], _ imaginary: inout [Float], direction: FFTDirection) {
        real.withUnsafeMutableBufferPointer { re in
            imaginary.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                vDSP_fft2d_zip(setup, &split, 1, 0, log2Columns, log2Rows, direction)
            }
        }
    }

    /// The `count` highest, well separated maxima of the correlation surface. A peak at index `p` means the view
    /// moved by `-p`, or by `n - p` if the move wrapped around the transform.
    private func findPeaks(in surface: [Float], count: Int) -> [Peak] {
        var peaks: [Peak] = []
        var surface = surface
        let total = vDSP_Length(columns * rows)
        for _ in 0..<count {
            var best: Float = 0
            var index: vDSP_Length = 0
            surface.withUnsafeBufferPointer { vDSP_maxvi($0.baseAddress!, 1, &best, &index, total) }
            guard best > -.infinity else {
                break
            }
            let x = Int(index) % columns, y = Int(index) / columns
            for dx in shifts(x, columns, width) {
                for dy in shifts(y, rows, height) {
                    peaks.append(Peak(dx: dx, dy: dy, strength: best))
                }
            }
            // Flatten the peak's neighbourhood, so the next one found is a distinct shift.
            for ny in (y - 2)...(y + 2) {
                for nx in (x - 2)...(x + 2) {
                    surface[((ny + rows) % rows) * columns + (nx + columns) % columns] = -.infinity
                }
            }
        }
        return peaks
    }

    /// The moves a peak index can mean, within the image's size.
    private func shifts(_ index: Int, _ n: Int, _ extent: Int) -> [Int] {
        var result = [-index]
        if index > 0, n - index < extent {
            result.append(n - index)
        }
        return result.filter { abs($0) < extent }
    }
}
