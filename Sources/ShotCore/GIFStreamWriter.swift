import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes a looping GIF a frame at a time, so memory stays flat however long it is. ImageIO's own encoder keeps every
/// frame until it finalises. Here it encodes each frame alone, cropped to what changed since the previous one with
/// unchanged pixels transparent, and its palette becomes that frame's local color table.
final class GIFStreamWriter {
    private let output: (Data) throws -> Void
    private var width = 0, height = 0
    /// ImageIO converts to sRGB when it writes a GIF, so frames are compared and cropped in it too.
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private var previous: [UInt32] = []
    private var current: [UInt32] = []
    private(set) var bytesWritten = 0

    init(output: @escaping (Data) throws -> Void) {
        self.output = output
    }

    /// Adds `image` for `delay` seconds; later frames are drawn at the first frame's size.
    func add(_ image: CGImage, delay: Double) throws {
        let first = previous.isEmpty
        if first {
            width = image.width
            height = image.height
            current = Array(repeating: 0, count: width * height)
        }
        try draw(image)
        let rect = first ? (x: 0, y: 0, width: width, height: height) : changedRect()
        let frame = try Self.encode(try crop(rect, masked: !first))

        var data = first ? header() : Data()
        let hundredths = UInt16(clamping: Int((delay * 100).rounded()))
        data += [0x21, 0xF9, 4, 1 << 2 | (frame.transparentIndex == nil ? 0 : 1)] + Self.little(hundredths) + [frame.transparentIndex ?? 0, 0]
        data += [0x2C] + Self.little(rect.x) + Self.little(rect.y) + Self.little(rect.width) + Self.little(rect.height)
        data += [0x80 | frame.interlaced | frame.colorTableBits]
        data += frame.colorTable + frame.imageData
        try write(data)
        swap(&previous, &current)
        if current.isEmpty { current = Array(repeating: 0, count: width * height) }
    }

    func finish() throws {
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

    private func draw(_ image: CGImage) throws {
        try current.withUnsafeMutableBytes { pixels in
            guard let colorSpace, let context = CGContext(
                data: pixels.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw GIFExporter.ExportError.cannotCreateDestination
            }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The smallest rectangle holding every pixel that differs from the previous frame; one pixel when none do, since
    /// a GIF frame can't be empty.
    private func changedRect() -> (x: Int, y: Int, width: Int, height: Int) {
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

    private func crop(_ rect: (x: Int, y: Int, width: Int, height: Int), masked: Bool) throws -> CGImage {
        var pixels = [UInt32](repeating: 0, count: rect.width * rect.height)
        for y in 0..<rect.height {
            let source = (rect.y + y) * width + rect.x
            for x in 0..<rect.width {
                let pixel = current[source + x]
                pixels[y * rect.width + x] = masked && pixel == previous[source + x] ? 0 : pixel
            }
        }
        guard let colorSpace, let provider = CGDataProvider(data: pixels.withUnsafeBytes { Data($0) } as CFData), let image = CGImage(
            width: rect.width, height: rect.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rect.width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else {
            throw GIFExporter.ExportError.cannotCreateDestination
        }
        return image
    }

    private struct EncodedFrame {
        var colorTable: Data
        var colorTableBits: UInt8
        var interlaced: UInt8
        var transparentIndex: UInt8?
        /// The LZW minimum code size and data sub-blocks, through the block terminator.
        var imageData: Data
    }

    private static func encode(_ image: CGImage) throws -> EncodedFrame {
        let data = NSMutableData()
        try autoreleasepool {
            guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, 1, nil) else {
                throw GIFExporter.ExportError.cannotCreateDestination
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw GIFExporter.ExportError.finalizeFailed
            }
        }
        guard let frame = parse([UInt8](data as Data)) else {
            throw GIFExporter.ExportError.finalizeFailed
        }
        return frame
    }

    /// Reads the color table, transparency and image data of the first frame of a GIF.
    private static func parse(_ bytes: [UInt8]) -> EncodedFrame? {
        func tableSize(_ packed: UInt8) -> Int { 3 << (Int(packed & 7) + 1) }
        func endOfSubBlocks(from start: Int) -> Int? {
            var index = start
            while index < bytes.count, bytes[index] != 0 { index += Int(bytes[index]) + 1 }
            return index < bytes.count ? index + 1 : nil
        }

        guard bytes.count > 13, bytes.starts(with: "GIF".utf8) else { return nil }
        var index = 13
        var table = Data(), tableBits: UInt8 = 0, transparentIndex: UInt8?
        if bytes[10] & 0x80 != 0 {
            guard index + tableSize(bytes[10]) <= bytes.count else { return nil }
            table = Data(bytes[index..<index + tableSize(bytes[10])])
            tableBits = bytes[10] & 7
            index += table.count
        }
        while index + 1 < bytes.count {
            switch bytes[index] {
            case 0x21:
                if bytes[index + 1] == 0xF9, index + 6 < bytes.count, bytes[index + 3] & 1 != 0 {
                    transparentIndex = bytes[index + 6]
                }
                guard let next = endOfSubBlocks(from: index + 2) else { return nil }
                index = next
            case 0x2C:
                guard index + 10 < bytes.count else { return nil }
                let packed = bytes[index + 9]
                index += 10
                if packed & 0x80 != 0 {
                    guard index + tableSize(packed) <= bytes.count else { return nil }
                    table = Data(bytes[index..<index + tableSize(packed)])
                    tableBits = packed & 7
                    index += table.count
                }
                guard !table.isEmpty, let end = endOfSubBlocks(from: index + 1) else { return nil }
                return EncodedFrame(colorTable: table, colorTableBits: tableBits, interlaced: packed & 0x40, transparentIndex: transparentIndex, imageData: Data(bytes[index..<end]))
            default:
                return nil
            }
        }
        return nil
    }

    private static func little(_ value: some BinaryInteger) -> Data {
        let value = UInt16(clamping: value)
        return Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }
}
