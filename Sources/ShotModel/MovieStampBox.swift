import Foundation

/// The project ID in an MP4 or MOV, as a top-level `uuid` box of Shot's own after the movie's boxes. Both formats are
/// built of size-and-type boxes that readers skip when they don't know them, so it plays everywhere, and Shot reads and
/// writes it without AVFoundation, whose handling of custom metadata changes between macOS releases: an MP4 export drops
/// `mdta` keys, and a custom iTunes atom comes back on macOS 27 but not on 26.
public enum MovieStampBox {
    /// The box's extended type, which marks it as Shot's.
    public static let userType: [UInt8] = [0xC1, 0x39, 0xE8, 0x73, 0x5D, 0x5B, 0x40, 0x8C, 0x84, 0x68, 0xDB, 0xAD, 0x54, 0x60, 0x85, 0xF6]
    /// Size, type and extended type.
    static let headerLength = 8 + 16

    /// One top-level box: where it starts, how long it is with its header, how long the header is, and its
    /// four-character type.
    public struct Box: Equatable, Sendable {
        public var offset: UInt64
        public var size: UInt64
        public var headerSize: UInt64
        public var type: String
    }

    /// The bytes of a box holding `id`.
    public static func box(id: String) -> Data {
        let payload = Data(id.utf8)
        var data = Data()
        let size = UInt32(headerLength + payload.count)
        data.append(contentsOf: [UInt8(size >> 24), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)])
        data.append(contentsOf: Array("uuid".utf8))
        data.append(contentsOf: userType)
        data.append(payload)
        return data
    }

    /// The box whose header is `header` (at least its first 16 bytes, or fewer at the end of the file), starting at
    /// `offset` in a file of `fileSize` bytes; `nil` when it isn't a whole box. A size of 0, which means "to the end of
    /// the file", counts as not whole, since nothing may follow it.
    public static func box(header: Data, at offset: UInt64, fileSize: UInt64) -> Box? {
        let bytes = [UInt8](header)
        guard bytes.count >= 8 else {
            return nil
        }
        var size = bytes[0..<4].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        var headerSize: UInt64 = 8
        let type = String(decoding: bytes[4..<8], as: UTF8.self)
        if size == 1 {
            guard bytes.count >= 16 else {
                return nil
            }
            size = bytes[8..<16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            headerSize = 16
        }
        guard size >= headerSize, offset <= fileSize, size <= fileSize - offset else {
            return nil
        }
        return Box(offset: offset, size: size, headerSize: headerSize, type: type)
    }

    /// Whether `boxes` are a whole movie that a box can be added after: each box starts where the last ended and the
    /// last ends at `fileSize`.
    public static func tiles(_ boxes: [Box], fileSize: UInt64) -> Bool {
        var end: UInt64 = 0
        for box in boxes {
            guard box.offset == end else {
                return false
            }
            end = box.offset + box.size
        }
        return !boxes.isEmpty && end == fileSize
    }

    /// The ID in a `uuid` box's contents after its size and type: the extended type, then the ID. `nil` when the box
    /// isn't Shot's.
    public static func id(inUUIDBody body: Data) -> String? {
        let bytes = [UInt8](body)
        guard bytes.count > 16, Array(bytes[0..<16]) == userType else {
            return nil
        }
        return String(bytes: bytes[16...], encoding: .utf8)
    }
}
