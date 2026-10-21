import Foundation
import Testing
@testable import ShotCore

/// A pixel as `GIFEncoder` takes it: red, green, blue and alpha bytes in that order in memory.
private func rgba(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) -> UInt32 {
    (UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | UInt32(a) << 24).littleEndian
}

/// A `width` by `height` frame of `background`, with `box` (x, y, width, height from the top left) in `color`.
private func frame(width: Int, height: Int, background: UInt32, box: (Int, Int, Int, Int)? = nil, color: UInt32 = 0) -> [UInt32] {
    var pixels = [UInt32](repeating: background, count: width * height)
    if let (x, y, w, h) = box {
        for row in y..<y + h {
            for column in x..<x + w { pixels[row * width + column] = color }
        }
    }
    return pixels
}

/// The same numbers on every run.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ z >> 30) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ z >> 27) &* 0x94D0_49BB_1331_11EB
        return z ^ z >> 31
    }
}

/// Test-only GIF decoder: the file's frames as a viewer shows them, each drawn over the one before.
private struct DecodedGIF {
    struct Frame {
        var x, y, width, height: Int
        var delay: Int
        var transparentIndex: Int?
        var colorCount: Int
        /// The whole canvas after this frame; pixels no frame has drawn are 0.
        var canvas: [UInt32]
    }

    var width = 0, height = 0
    var loopCount: Int?
    var frames: [Frame] = []

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        var index = 0
        func byte() -> Int? {
            guard index < bytes.count else { return nil }
            defer { index += 1 }
            return Int(bytes[index])
        }
        func word() -> Int? {
            guard let low = byte(), let high = byte() else { return nil }
            return low | high << 8
        }
        func subBlocks() -> [UInt8]? {
            var out: [UInt8] = []
            while let count = byte() {
                if count == 0 { return out }
                guard index + count <= bytes.count else { return nil }
                out += bytes[index..<index + count]
                index += count
            }
            return nil
        }

        guard bytes.starts(with: Array("GIF89a".utf8)) else { return nil }
        index = 6
        guard let width = word(), let height = word(), let packed = byte(), byte() != nil, byte() != nil, packed & 0x80 == 0 else { return nil }
        self.width = width
        self.height = height
        var canvas = [UInt32](repeating: 0, count: width * height)
        var delay = 0, transparentIndex: Int?
        while let introducer = byte() {
            switch introducer {
            case 0x21:
                guard let label = byte(), let body = subBlocks() else { return nil }
                if label == 0xF9, body.count == 4 {
                    delay = Int(body[1]) | Int(body[2]) << 8
                    transparentIndex = body[0] & 1 != 0 ? Int(body[3]) : nil
                } else if label == 0xFF, body.count == 14, String(decoding: body[0..<11], as: UTF8.self) == "NETSCAPE2.0" {
                    loopCount = Int(body[12]) | Int(body[13]) << 8
                }
            case 0x2C:
                guard let x = word(), let y = word(), let w = word(), let h = word(), let packed = byte(), packed & 0x80 != 0, packed & 0x40 == 0 else { return nil }
                let colorCount = 2 << (packed & 7)
                guard index + colorCount * 3 <= bytes.count else { return nil }
                let table = Array(bytes[index..<index + colorCount * 3])
                index += colorCount * 3
                guard let minimumCodeSize = byte(), let lzw = subBlocks(), let indices = Self.decompress(lzw, minimumCodeSize: minimumCodeSize), indices.count == w * h, x + w <= width, y + h <= height else { return nil }
                for row in 0..<h {
                    for column in 0..<w {
                        let color = Int(indices[row * w + column])
                        guard color != transparentIndex else { continue }
                        canvas[(y + row) * width + x + column] = rgba(table[color * 3], table[color * 3 + 1], table[color * 3 + 2])
                    }
                }
                frames.append(Frame(x: x, y: y, width: w, height: h, delay: delay, transparentIndex: transparentIndex, colorCount: colorCount, canvas: canvas))
                delay = 0
                transparentIndex = nil
            case 0x3B:
                return
            default:
                return nil
            }
        }
        return nil
    }

    static func decompress(_ data: [UInt8], minimumCodeSize: Int) -> [UInt8]? {
        let clear = 1 << minimumCodeSize, end = clear + 1
        let roots = (0..<clear).map { [UInt8($0)] }
        var table = roots + [[], []]
        var codeSize = minimumCodeSize + 1
        var bitIndex = 0, out: [UInt8] = [], previous: [UInt8]?
        while bitIndex + codeSize <= data.count * 8 {
            var code = 0
            for bit in 0..<codeSize where data[(bitIndex + bit) / 8] >> ((bitIndex + bit) % 8) & 1 != 0 {
                code |= 1 << bit
            }
            bitIndex += codeSize
            if code == clear {
                table = roots + [[], []]
                codeSize = minimumCodeSize + 1
                previous = nil
                continue
            }
            if code == end { return out }
            let entry: [UInt8]
            if code < table.count, code != clear, code != end {
                entry = table[code]
            } else if code == table.count, let previous {
                entry = previous + [previous[0]]
            } else {
                return nil
            }
            out += entry
            if let previous, table.count < 4096 {
                table.append(previous + [entry[0]])
            }
            previous = entry
            if table.count == 1 << codeSize, codeSize < 12 { codeSize += 1 }
        }
        return nil
    }
}

private func encode(_ frames: [[UInt32]], width: Int, height: Int, delays: [Double]) throws -> (data: Data, bytesWritten: Int) {
    var data = Data()
    let encoder = GIFEncoder(width: width, height: height) { data += $0 }
    for (frame, delay) in zip(frames, delays) {
        var pixels = frame
        try encoder.add(&pixels, delay: delay)
    }
    try encoder.finish()
    return (data, encoder.bytesWritten)
}

@Test func aGIFStoresOnlyWhatChangedAndStillPlaysEveryFrame() throws {
    let blue = rgba(0, 0, 255), red = rgba(255, 0, 0)
    let frames = [
        frame(width: 64, height: 48, background: blue),
        frame(width: 64, height: 48, background: blue, box: (4, 8, 10, 10), color: red),
        frame(width: 64, height: 48, background: blue, box: (4, 8, 10, 10), color: red),
    ]
    let (data, bytesWritten) = try encode(frames, width: 64, height: 48, delays: [0.07, 0.06, 0.5])
    #expect(bytesWritten == data.count)

    let gif = try #require(DecodedGIF(data))
    #expect(gif.width == 64 && gif.height == 48)
    #expect(gif.loopCount == 0)
    #expect(gif.frames.map(\.delay) == [7, 6, 50])
    #expect(gif.frames.map { [$0.x, $0.y, $0.width, $0.height] } == [[0, 0, 64, 48], [4, 8, 10, 10], [0, 0, 1, 1]])
    #expect(gif.frames.map(\.canvas) == frames)
}

@Test func unchangedPixelsInsideTheChangedRectAreLeftTransparent() throws {
    let grey = rgba(128, 128, 128), green = rgba(0, 200, 0)
    var second = frame(width: 20, height: 10, background: grey)
    second[0] = green
    second[9 * 20 + 19] = green
    let frames = [frame(width: 20, height: 10, background: grey), second]
    let gif = try #require(DecodedGIF(try encode(frames, width: 20, height: 10, delays: [0.1, 0.1]).data))
    #expect(gif.frames[0].transparentIndex == nil)
    // The second frame covers the whole canvas but holds one color, green, and the transparent index after it.
    #expect(gif.frames[1].transparentIndex == 1)
    #expect(gif.frames[1].colorCount == 2)
    #expect(gif.frames.map(\.canvas) == frames)
}

@Test func aFrameWithManyColorsGetsAFullTableCloseToTheOriginal() throws {
    // Every 6-bit-per-channel color, far more than one table holds.
    let width = 512, height = 512
    let pixels = (0..<width * height).map { (i: Int) -> UInt32 in
        let r = UInt8(i & 63) << 2, g = UInt8(i >> 6 & 63) << 2, b = UInt8(i >> 12 & 63) << 2
        return rgba(r, g, b)
    }
    let gif = try #require(DecodedGIF(try encode([pixels], width: width, height: height, delays: [0.1]).data))
    #expect(gif.frames[0].colorCount == 256)
    let decoded = gif.frames[0].canvas
    var error = 0
    for (a, b) in zip(pixels, decoded) {
        for shift in [0, 8, 16] {
            error += abs(Int(UInt32(littleEndian: a) >> shift & 0xFF) - Int(UInt32(littleEndian: b) >> shift & 0xFF))
        }
    }
    let mean = Double(error) / Double(pixels.count * 3)
    // ImageIO's encoder, which Shot used before, averaged 10.7 on this frame.
    #expect(mean < 11, "mean error per channel \(mean)")
}

@Test func aFewColorsKeepTheirExactValues() {
    // Colors less than 8 apart in every channel share a histogram bin and merge, as ImageIO's encoder merged them.
    let colors = [rgba(9, 2, 3), rgba(250, 128, 7), rgba(0, 0, 0), rgba(255, 255, 255)]
    let frame = ColorQuantizer.quantize((0..<400).map { colors[$0 % 4] })
    #expect(frame.colorCount == 4)
    #expect(frame.transparentIndex == nil)
    let decoded = frame.indices.map { i in rgba(frame.palette[Int(i) * 3], frame.palette[Int(i) * 3 + 1], frame.palette[Int(i) * 3 + 2]) }
    #expect(decoded == (0..<400).map { colors[$0 % 4] })
}

@Test func transparentPixelsTakeTheIndexAfterTheColorsAndLeaveRoomForIt() {
    var pixels = (0..<1024).map { i in rgba(UInt8(i & 31) << 3, UInt8(i >> 5) << 3, 100) }
    pixels[5] = rgba(0, 0, 0, 0)
    pixels[6] = rgba(10, 10, 10, 127)
    let frame = ColorQuantizer.quantize(pixels)
    #expect(frame.colorCount == 255)
    #expect(frame.transparentIndex == 255)
    #expect(frame.indices[5] == 255 && frame.indices[6] == 255)
    #expect(frame.indices.enumerated().allSatisfy { $0.offset == 5 || $0.offset == 6 || $0.element < 255 })
}

@Test func halfOpaquePixelsAreStoredAsTheirStraightColor() {
    let frame = ColorQuantizer.quantize([rgba(64, 32, 0, 128)])
    #expect(frame.palette == [128, 64, 0])
    #expect(frame.indices == [0])
}

@Test func lzwRoundTripsPastTheCodeTableLimit() throws {
    var random = SplitMix(state: 652)
    let noisy = (0..<200_000).map { _ in UInt8.random(in: 0...255, using: &random) }
    let runs = (0..<200_000).map { UInt8($0 / 300 % 256) }
    let small = (0..<50_000).map { _ in UInt8.random(in: 0...3, using: &random) }
    for (indices, minimumCodeSize) in [(noisy, 8), (runs, 8), (small, 2), ([7], 3), ([0, 0], 2), ([], 2)] {
        let data = [UInt8](GIFEncoder.compress(indices, minimumCodeSize: minimumCodeSize))
        #expect(Int(data[0]) == minimumCodeSize)
        #expect(data.last == 0)
        var blocks: [UInt8] = [], index = 1
        while data[index] != 0 {
            #expect(Int(data[index]) <= 255)
            blocks += data[index + 1..<index + 1 + Int(data[index])]
            index += Int(data[index]) + 1
        }
        #expect(index == data.count - 1)
        #expect(DecodedGIF.decompress(blocks, minimumCodeSize: minimumCodeSize) == indices, "\(indices.count) indices, code size \(minimumCodeSize)")
    }
}

@Test func anEncoderWhoseOutputFailsThrowsAndCountsNothing() {
    struct DiskFull: Error {}
    let encoder = GIFEncoder(width: 4, height: 4) { _ in throw DiskFull() }
    var pixels = frame(width: 4, height: 4, background: rgba(1, 2, 3))
    #expect(throws: DiskFull.self) {
        try encoder.add(&pixels, delay: 0.1)
    }
    #expect(encoder.bytesWritten == 0)
}
