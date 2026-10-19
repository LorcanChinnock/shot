import Foundation

/// Reads and adds the JPEG marker segments `ImageHeader` describes.
enum JPEGSegments {
    static let app0: UInt8 = 0xE0
    static let app1: UInt8 = 0xE1
    static let jfif = Data("JFIF\0".utf8)
    static let exif = Data("Exif\0\0".utf8)
    static let xmp = Data("http://ns.adobe.com/xap/1.0/\0".utf8)
    static let extendedXMP = Data("http://ns.adobe.com/xmp/extension/\0".utf8)
    /// The most a segment holds after its marker and length.
    static let maxPayload = 65533
    /// What ImageIO puts in each extended XMP segment.
    static let extendedChunk = 65000

    /// Each marker segment before the image data, as its marker and what follows its length; `nil` when `data` isn't
    /// a JPEG.
    static func segments(of data: Data) -> [(marker: UInt8, payload: Data)]? {
        let reader = ByteReader(data: data)
        guard reader.byte(0) == 0xFF, reader.byte(1) == 0xD8 else {
            return nil
        }
        var segments: [(marker: UInt8, payload: Data)] = []
        var offset = 2
        while reader.byte(offset) == 0xFF, var marker = reader.byte(offset + 1) {
            // Any number of 0xFF bytes may pad a marker.
            while marker == 0xFF {
                offset += 1
                guard let next = reader.byte(offset + 1) else {
                    return segments
                }
                marker = next
            }
            switch marker {
            case 0xD9, 0xDA:
                return segments
            case 0x01, 0xD0 ... 0xD7:
                offset += 2
            default:
                guard let length = reader.uint16(offset + 2), length >= 2, let payload = reader.bytes(offset + 4, length - 2) else {
                    return segments
                }
                segments.append((UInt8(marker), payload))
                offset += 2 + length
            }
        }
        return segments
    }

    static func header(of data: Data) -> ImageHeader? {
        guard let segments = segments(of: data) else {
            return nil
        }
        // Every start-of-frame marker but those that share its range: DHT, JPG and DAC.
        let frames: Set<UInt8> = Set(0xC0 ... 0xCF).subtracting([0xC4, 0xC8, 0xCC])
        guard let frame = segments.first(where: { frames.contains($0.marker) }).map({ ByteReader(data: $0.payload) }),
              let height = frame.uint16(1), let width = frame.uint16(3), width > 0, height > 0
        else {
            return nil
        }
        var dpi: Double?, exifData: Exif?, standardXMP: String?
        var extended: [(guid: Data, total: Int, offset: Int, chunk: Data)] = []
        for segment in segments {
            let body = ByteReader(data: segment.payload)
            switch segment.marker {
            case app0 where body.starts(with: jfif):
                // Units: 1 is per inch, 2 per centimetre, and 0 only an aspect ratio.
                if let units = body.byte(7), let density = body.uint16(8), density > 0, units == 1 || units == 2 {
                    dpi = units == 1 ? Double(density) : Double(density) * 2.54
                }
            case app1 where body.starts(with: exif):
                exifData = body.bytes(exif.count, body.count - exif.count).flatMap(Exif.init)
            case app1 where body.starts(with: xmp):
                standardXMP = body.bytes(xmp.count, body.count - xmp.count).map { String(decoding: $0, as: UTF8.self) }
            case app1 where body.starts(with: extendedXMP):
                let start = extendedXMP.count
                if let guid = body.bytes(start, 32), let total = body.uint32(start + 32), let offset = body.uint32(start + 36),
                   let chunk = body.bytes(start + 40, body.count - start - 40) {
                    extended.append((Data(guid), total, offset, chunk))
                }
            default:
                break
            }
        }
        let note = standardXMP.flatMap { XMP.property("HasExtendedXMP", namespace: XMP.noteNamespace, in: $0) }
        let extendedText = note.flatMap { guid in assemble(extended.filter { $0.guid == Data(guid.utf8) }) }
        let metadata = ImageMetadata(userComment: exifData?.userComment) { name in
            [standardXMP, extendedText].lazy.compactMap { $0.flatMap { XMP.property(name, namespace: ImageMetadata.xmpNamespace, in: $0) } }.first
        }
        return ImageHeader(format: .jpeg, width: width, height: height, dpi: dpi ?? exifData?.dpi, metadata: metadata)
    }

    /// The extended XMP its segments hold, or `nil` when they don't cover it.
    private static func assemble(_ parts: [(guid: Data, total: Int, offset: Int, chunk: Data)]) -> String? {
        guard let total = parts.first?.total, total > 0, total <= parts.reduce(0, { $0 + $1.chunk.count }) else {
            return nil
        }
        var text = Data(count: total)
        for part in parts {
            guard part.total == total, part.offset + part.chunk.count <= total else {
                return nil
            }
            text.replaceSubrange(part.offset ..< part.offset + part.chunk.count, with: part.chunk)
        }
        return String(decoding: text, as: UTF8.self)
    }

    /// `data` with its JFIF segment saying `dpi`, then an Exif segment for the window shadow and XMP for the record and
    /// project, as ImageIO places them. A packet too big for one segment keeps the record in extended XMP segments.
    static func adding(dpi: Double, metadata: ImageMetadata, to data: Data) -> Data? {
        let reader = ByteReader(data: data)
        guard reader.byte(0) == 0xFF, reader.byte(1) == 0xD8 else {
            return nil
        }
        var rest = Data(data.dropFirst(2))
        let first = ByteReader(data: rest)
        if first.byte(0) == 0xFF, first.byte(1) == Int(app0), first.starts(with: jfif, at: 4), let length = first.uint16(2) {
            rest = Data(rest.dropFirst(2 + length))
        }
        let density = Data.bigEndian(min(65535, max(1, Int(dpi.rounded()))), size: 2)
        var segments = [segment(app0, jfif + [1, 1, 1] + density + density + [0, 0])]
        if metadata.windowShadow {
            segments.append(segment(app1, exif + Exif.tiff(userComment: ImageMetadata.windowShadowComment)))
        }
        let properties = metadata.xmpProperties
        if !properties.isEmpty {
            let packet = Data(XMP.packet(properties).utf8)
            if xmp.count + packet.count <= maxPayload {
                segments.append(segment(app1, xmp + packet))
            } else {
                let guid = Data(UUID().uuidString.replacingOccurrences(of: "-", with: "").utf8)
                let standard = XMP.packet(properties.filter { $0.name != "record" }, extendedGUID: String(decoding: guid, as: UTF8.self))
                segments.append(segment(app1, xmp + Data(standard.utf8)))
                let full = Data(XMP.packet(properties.filter { $0.name == "record" }, wrapped: false).utf8)
                for offset in stride(from: 0, to: full.count, by: extendedChunk) {
                    let chunk = full[full.startIndex + offset ..< full.startIndex + min(full.count, offset + extendedChunk)]
                    segments.append(segment(app1, extendedXMP + guid + Data.bigEndian(full.count, size: 4) + Data.bigEndian(offset, size: 4) + chunk))
                }
            }
        }
        guard segments.allSatisfy({ $0 != nil }) else {
            return nil
        }
        return Data([0xFF, 0xD8]) + segments.compactMap { $0 }.reduce(Data(), +) + rest
    }

    /// `nil` when `payload` is too big for a segment.
    private static func segment(_ marker: UInt8, _ payload: Data) -> Data? {
        payload.count <= maxPayload ? Data([0xFF, marker]) + Data.bigEndian(payload.count + 2, size: 2) + payload : nil
    }
}
