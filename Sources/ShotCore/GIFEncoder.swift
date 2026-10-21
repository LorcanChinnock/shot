import Foundation

/// Writes a looping GIF a frame at a time, so memory stays flat however long it is. Each frame is cropped to what
/// changed since the previous one, with unchanged pixels transparent, and `ColorQuantizer` gives it its own color
/// table. It works on RGBA pixels, so it's tested without a file; `GIFStreamWriter` draws each image into them.
public final class GIFEncoder {
    public let width: Int
    public let height: Int
    private let output: (Data) throws -> Void
    private var previous: [UInt32]
    private var started = false
    public private(set) var bytesWritten = 0

    public init(width: Int, height: Int, output: @escaping (Data) throws -> Void) {
        precondition(width > 0 && height > 0)
        self.width = width
        self.height = height
        self.output = output
        previous = Array(repeating: 0, count: width * height)
    }

    /// Adds `pixels` for `delay` seconds: `width × height` of them, top row first, each one's premultiplied red, green,
    /// blue and alpha bytes in that order in memory, as `Bitmap` lays them out. On return `pixels` holds the previous
    /// frame, so the caller can draw the next one into it without allocating.
    public func add(_ pixels: inout [UInt32], delay: Double) throws {
        precondition(pixels.count == width * height)
        let first = !started
        let rect = first ? (x: 0, y: 0, width: width, height: height) : changedRect(pixels)
        let frame = ColorQuantizer.quantize(crop(pixels, to: rect, masked: !first))
        var tableBits = 0
        while 2 << tableBits < frame.colorCount + (frame.transparentIndex == nil ? 0 : 1) { tableBits += 1 }

        var data = first ? header() : Data()
        let hundredths = UInt16(clamping: Int((delay * 100).rounded()))
        data += [0x21, 0xF9, 4, 1 << 2 | (frame.transparentIndex == nil ? 0 : 1)] + Self.little(hundredths) + [frame.transparentIndex ?? 0, 0]
        data += [0x2C] + Self.little(rect.x) + Self.little(rect.y) + Self.little(rect.width) + Self.little(rect.height)
        data += [0x80 | UInt8(tableBits)]
        data += frame.palette + [UInt8](repeating: 0, count: (2 << tableBits) * 3 - frame.palette.count)
        data += Self.compress(frame.indices, minimumCodeSize: max(2, tableBits + 1))
        try write(data)
        swap(&previous, &pixels)
        started = true
    }

    public func finish() throws {
        try write(Data([0x3B]))
    }

    private func write(_ data: Data) throws {
        try output(data)
        bytesWritten += data.count
    }

    private func header() -> Data {
        var data = Data("GIF89a".utf8) + Self.little(width) + Self.little(height) + [0, 0, 0]
        data += [0x21, 0xFF, 11] + Data("NETSCAPE2.0".utf8) + [3, 1, 0, 0, 0]
        return data
    }

    /// The smallest rectangle holding every pixel that differs from the previous frame; one pixel when none do, since
    /// a GIF frame can't be empty.
    private func changedRect(_ current: [UInt32]) -> (x: Int, y: Int, width: Int, height: Int) {
        var minX = width, maxX = -1, minY = height, maxY = -1
        current.withUnsafeBufferPointer { current in
            previous.withUnsafeBufferPointer { previous in
                for y in 0..<height {
                    let row = y * width
                    guard let first = (0..<width).first(where: { current[row + $0] != previous[row + $0] }) else { continue }
                    let last = (first..<width).last { current[row + $0] != previous[row + $0] }!
                    minX = min(minX, first)
                    maxX = max(maxX, last)
                    minY = min(minY, y)
                    maxY = y
                }
            }
        }
        return maxX < 0 ? (0, 0, 1, 1) : (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    private func crop(_ current: [UInt32], to rect: (x: Int, y: Int, width: Int, height: Int), masked: Bool) -> [UInt32] {
        var pixels = [UInt32](repeating: 0, count: rect.width * rect.height)
        current.withUnsafeBufferPointer { current in
            previous.withUnsafeBufferPointer { previous in
                for y in 0..<rect.height {
                    let source = (rect.y + y) * width + rect.x
                    for x in 0..<rect.width {
                        let pixel = current[source + x]
                        pixels[y * rect.width + x] = masked && pixel == previous[source + x] ? 0 : pixel
                    }
                }
            }
        }
        return pixels
    }

    /// `indices` as GIF image data: the LZW minimum code size, the LZW codes in sub-blocks of up to 255 bytes, and the
    /// block terminator. Every index must be less than `1 << minimumCodeSize`.
    static func compress(_ indices: [UInt8], minimumCodeSize: Int) -> Data {
        let clear = 1 << minimumCodeSize, end = clear + 1, maxCode = 1 << 12
        var codeSize = minimumCodeSize + 1, next = clear + 2
        // Strings seen so far, keyed by their prefix's code and their last index, in an open-addressed table of the
        // size compress(1) uses for 12-bit codes.
        let tableSize = 5003
        var keys = [Int32](repeating: -1, count: tableSize)
        var codes = [Int16](repeating: 0, count: tableSize)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(indices.count / 2)
        var bits = 0, bitCount = 0
        func emit(_ code: Int) {
            bits |= code << bitCount
            bitCount += codeSize
            while bitCount >= 8 {
                bytes.append(UInt8(truncatingIfNeeded: bits))
                bits >>= 8
                bitCount -= 8
            }
        }

        emit(clear)
        indices.withUnsafeBufferPointer { indices in
            guard var prefix = indices.first.map(Int.init) else { return }
            for byte in indices.dropFirst() {
                let index = Int(byte)
                let key = Int32(prefix << 8 | index)
                var slot = index << 4 ^ prefix
                let step = slot == 0 ? 1 : tableSize - slot
                while keys[slot] != key, keys[slot] >= 0 {
                    slot -= step
                    if slot < 0 { slot += tableSize }
                }
                if keys[slot] == key {
                    prefix = Int(codes[slot])
                    continue
                }
                emit(prefix)
                if next < maxCode {
                    keys[slot] = key
                    codes[slot] = Int16(next)
                    next += 1
                    // A decoder adds each string a code later, so it widens its codes once `next` passes the limit.
                    if next > 1 << codeSize { codeSize += 1 }
                } else {
                    emit(clear)
                    keys = Array(repeating: -1, count: tableSize)
                    codeSize = minimumCodeSize + 1
                    next = clear + 2
                }
                prefix = index
            }
            emit(prefix)
            // The decoder adds the last string as it reads the last code, so the end code may already be wider.
            if next == 1 << codeSize, codeSize < 12 { codeSize += 1 }
        }
        emit(end)
        if bitCount > 0 { bytes.append(UInt8(truncatingIfNeeded: bits)) }

        var data = Data([UInt8(minimumCodeSize)])
        data.reserveCapacity(bytes.count + bytes.count / 255 + 3)
        for start in stride(from: 0, to: bytes.count, by: 255) {
            let block = bytes[start..<min(start + 255, bytes.count)]
            data.append(UInt8(block.count))
            data += block
        }
        data.append(0)
        return data
    }

    private static func little(_ value: some BinaryInteger) -> Data {
        let value = UInt16(clamping: value)
        return Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }
}
