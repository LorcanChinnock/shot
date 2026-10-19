import Foundation

/// The two things Shot reads from Exif, a TIFF structure: the resolution and the user comment.
struct Exif: Equatable {
    var dpi: Double?
    var userComment: String?

    private static let xResolution = 0x011A
    private static let resolutionUnit = 0x0128
    private static let exifIFD = 0x8769
    private static let userCommentTag = 0x9286
    private static let ascii = Data("ASCII\0\0\0".utf8)
    private static let unicode = Data("UNICODE\0".utf8)

    /// `nil` when `tiff` isn't a TIFF structure.
    init?(tiff: Data) {
        var reader = ByteReader(data: tiff)
        switch reader.bytes(0, 2).map({ Data($0) }) {
        case Data("MM".utf8): reader.bigEndian = true
        case Data("II".utf8): reader.bigEndian = false
        default: return nil
        }
        guard reader.uint16(2) == 42, let first = reader.uint32(4) else {
            return nil
        }
        let ifd0 = Self.entries(reader, at: first)
        if let x = ifd0[Self.xResolution].flatMap({ reader.uint32($0 + 8) }), let numerator = reader.uint32(x), let denominator = reader.uint32(x + 4), numerator > 0, denominator > 0 {
            // 2 is inches, the default, and 3 centimetres.
            let perCentimetre = ifd0[Self.resolutionUnit].flatMap { reader.uint16($0 + 8) } == 3
            dpi = Double(numerator) / Double(denominator) * (perCentimetre ? 2.54 : 1)
        }
        if let sub = ifd0[Self.exifIFD].flatMap({ reader.uint32($0 + 8) }), let entry = Self.entries(reader, at: sub)[Self.userCommentTag],
           let count = reader.uint32(entry + 4) {
            let offset = count <= 4 ? entry + 8 : reader.uint32(entry + 8)
            userComment = offset.flatMap { reader.bytes($0, count) }.flatMap { Self.comment($0, bigEndian: reader.bigEndian) }
        }
    }

    /// The offset of each entry of the directory at `offset`, by tag.
    private static func entries(_ reader: ByteReader, at offset: Int) -> [Int: Int] {
        guard let count = reader.uint16(offset) else {
            return [:]
        }
        var entries: [Int: Int] = [:]
        for index in 0 ..< count {
            let entry = offset + 2 + index * 12
            if let tag = reader.uint16(entry) {
                entries[tag] = entry
            }
        }
        return entries
    }

    /// A user comment is its character code in 8 bytes, then the text.
    private static func comment(_ data: Data, bigEndian: Bool) -> String? {
        let code = Data(data.prefix(8)), text = Data(data.dropFirst(8))
        let decoded = code == unicode ? String(data: text, encoding: bigEndian ? .utf16BigEndian : .utf16LittleEndian) : String(data: text, encoding: .utf8)
        return decoded?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }

    /// A big-endian TIFF structure holding only `comment` as the user comment.
    static func tiff(userComment comment: String) -> Data {
        let text = comment.canBeConverted(to: .ascii) ? ascii + Data(comment.utf8) : unicode + (comment.data(using: .utf16BigEndian) ?? Data())
        // The header, the first directory at 8 pointing to the Exif directory at 26, and that pointing to the text at 44.
        var tiff = Data("MM".utf8) + Data.bigEndian(42, size: 2) + Data.bigEndian(8, size: 4)
        tiff += Data.bigEndian(1, size: 2) + entry(exifIFD, type: 4, count: 1, value: 26) + Data.bigEndian(0, size: 4)
        tiff += Data.bigEndian(1, size: 2) + entry(userCommentTag, type: 7, count: text.count, value: 44) + Data.bigEndian(0, size: 4)
        return tiff + text
    }

    private static func entry(_ tag: Int, type: Int, count: Int, value: Int) -> Data {
        Data.bigEndian(tag, size: 2) + Data.bigEndian(type, size: 2) + Data.bigEndian(count, size: 4) + Data.bigEndian(value, size: 4)
    }
}
