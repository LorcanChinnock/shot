import Foundation

/// Reads and adds the PNG chunks `ImageHeader` describes.
enum PNGChunks {
    static let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    /// The `iTXt` keyword XMP goes under.
    static let xmpKeyword = "XML:com.adobe.xmp"

    /// Each chunk's type and data in order, as far as `data` holds whole chunks; `nil` when it isn't a PNG.
    static func chunks(of data: Data) -> [(type: String, data: Data)]? {
        let reader = ByteReader(data: data)
        guard reader.starts(with: signature) else {
            return nil
        }
        var chunks: [(type: String, data: Data)] = []
        var offset = signature.count
        while let length = reader.uint32(offset), let type = reader.bytes(offset + 4, 4), let body = reader.bytes(offset + 8, length) {
            chunks.append((String(decoding: type, as: UTF8.self), body))
            offset += 12 + length
        }
        return chunks
    }

    static func header(of data: Data) -> ImageHeader? {
        guard let chunks = chunks(of: data), let ihdr = chunks.first, ihdr.type == "IHDR" else {
            return nil
        }
        let size = ByteReader(data: ihdr.data)
        guard let width = size.uint32(0), let height = size.uint32(4), width > 0, height > 0 else {
            return nil
        }
        var dpi: Double?, exif: Exif?, xmp: String?
        for chunk in chunks {
            let body = ByteReader(data: chunk.data)
            switch chunk.type {
            case "pHYs":
                // Per metre. ImageIO reads 5669 as 144 DPI, so it rounds to a whole DPI, as this does.
                if let perMetre = body.uint32(0), perMetre > 0, body.byte(8) == 1 {
                    dpi = (Double(perMetre) * 0.0254).rounded()
                }
            case "eXIf":
                exif = Exif(tiff: chunk.data)
            case "iTXt":
                xmp = xmp ?? xmpText(chunk.data)
            default:
                break
            }
        }
        let metadata = ImageMetadata(userComment: exif?.userComment) { name in
            xmp.flatMap { XMP.property(name, namespace: ImageMetadata.xmpNamespace, in: $0) }
        }
        return ImageHeader(format: .png, width: width, height: height, dpi: dpi ?? exif?.dpi, metadata: metadata)
    }

    /// The XMP an `iTXt` chunk holds, when it's XMP and not compressed, which neither Shot nor ImageIO does.
    private static func xmpText(_ body: Data) -> String? {
        let fields = body.split(separator: 0, maxSplits: 1, omittingEmptySubsequences: false)
        guard fields.count == 2, String(decoding: fields[0], as: UTF8.self) == xmpKeyword else {
            return nil
        }
        let rest = ByteReader(data: fields[1])
        guard rest.byte(0) == 0, let afterFlags = rest.bytes(2, rest.count - 2) else {
            return nil
        }
        // The language and translated keyword, then the text.
        let text = afterFlags.split(separator: 0, maxSplits: 2, omittingEmptySubsequences: false)
        return text.count == 3 ? String(decoding: text[2], as: UTF8.self) : nil
    }

    /// `data` with a `pHYs` chunk for `dpi`, an `eXIf` chunk for the window shadow and an `iTXt` chunk of XMP for the
    /// record and project after its `IHDR`, as ImageIO places them.
    static func adding(dpi: Double, metadata: ImageMetadata, to data: Data) -> Data? {
        let reader = ByteReader(data: data)
        guard reader.starts(with: signature), let length = reader.uint32(signature.count), reader.starts(with: Data("IHDR".utf8), at: signature.count + 4) else {
            return nil
        }
        let afterHeader = signature.count + 12 + length
        let perMetre = Data.bigEndian(Int((dpi / 0.0254).rounded()), size: 4)
        var added = chunk("pHYs", perMetre + perMetre + [1])
        if metadata.windowShadow {
            added += chunk("eXIf", Exif.tiff(userComment: ImageMetadata.windowShadowComment))
        }
        let properties = metadata.xmpProperties
        if !properties.isEmpty {
            added += chunk("iTXt", Data(xmpKeyword.utf8) + [0, 0, 0, 0, 0] + Data(XMP.packet(properties).utf8))
        }
        return Data(data.prefix(afterHeader)) + added + Data(data.dropFirst(afterHeader))
    }

    static func chunk(_ type: String, _ body: Data) -> Data {
        let typed = Data(type.utf8) + body
        return Data.bigEndian(body.count, size: 4) + typed + Data.bigEndian(Int(crc32(typed)), size: 4)
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { n in
        (0 ..< 8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    static func crc32(_ bytes: Data) -> UInt32 {
        ~bytes.reduce(~UInt32(0)) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }
}
