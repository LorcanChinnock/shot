import Foundation

/// What a GIF says without decoding its pictures: its size, from its logical screen, and how many frames it holds, as
/// ImageIO counts them on a Mac. Linux has no GIF decoder, so `shot info` reads a GIF through this.
public struct GIFHeader: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var frames: Int

    /// `nil` when `data` isn't a GIF with at least one frame. A file cut short counts the frames before the cut.
    public init?(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 13, bytes[0 ..< 6].elementsEqual("GIF87a".utf8) || bytes[0 ..< 6].elementsEqual("GIF89a".utf8) else {
            return nil
        }
        width = Int(bytes[6]) | Int(bytes[7]) << 8
        height = Int(bytes[8]) | Int(bytes[9]) << 8
        frames = 0
        var index = 13 + Self.colorTableSize(bytes[10])
        /// Moves past a run of sub-blocks, each a length then that many bytes, ending at a zero length.
        func skipSubBlocks() -> Bool {
            while index < bytes.count {
                let length = Int(bytes[index])
                index += 1 + length
                if length == 0 {
                    return true
                }
            }
            return false
        }
        scan: while index < bytes.count {
            switch bytes[index] {
            case 0x21:
                // An extension: its label, then its sub-blocks.
                index += 2
                guard skipSubBlocks() else { break scan }
            case 0x2C:
                // An image: its descriptor, its own colour table, the LZW code size, then its sub-blocks.
                guard index + 10 < bytes.count else { break scan }
                index += 10 + Self.colorTableSize(bytes[index + 9]) + 1
                guard skipSubBlocks() else { break scan }
                frames += 1
            default:
                // 0x3B ends the file; anything else isn't a GIF block.
                break scan
            }
        }
        guard width > 0, height > 0, frames > 0 else {
            return nil
        }
    }

    init(width: Int, height: Int, frames: Int) {
        self.width = width
        self.height = height
        self.frames = frames
    }

    /// The bytes of the colour table that a packed field's top bit says follows, of 2^(n+1) colours.
    private static func colorTableSize(_ packed: UInt8) -> Int {
        packed & 0x80 == 0 ? 0 : 3 << (Int(packed & 7) + 1)
    }
}
