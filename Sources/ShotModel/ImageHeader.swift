import Foundation

/// What a PNG or JPEG says besides its pixels: its size, its DPI and Shot's metadata, read from the chunks and markers
/// ImageIO uses on a Mac, so a file written on either platform reads the same on the other. A PNG keeps the DPI in
/// `pHYs`, the window shadow in an `eXIf` chunk's user comment and the record and project in an `iTXt` chunk of XMP.
/// A JPEG keeps them in a JFIF `APP0` segment, an Exif `APP1` and an XMP `APP1`, with a record too big for one segment
/// in extended XMP segments, as ImageIO splits it.
public struct ImageHeader: Equatable, Sendable {
    public var format: ImageFormat
    public var width: Int
    public var height: Int
    /// `nil` when the file doesn't say.
    public var dpi: Double?
    public var metadata: ImageMetadata

    /// `nil` when `data` isn't a PNG or JPEG.
    public init?(_ data: Data) {
        if let header = PNGChunks.header(of: data) ?? JPEGSegments.header(of: data) {
            self = header
        } else {
            return nil
        }
    }

    init(format: ImageFormat, width: Int, height: Int, dpi: Double?, metadata: ImageMetadata) {
        self.format = format
        self.width = width
        self.height = height
        self.dpi = dpi
        self.metadata = metadata
    }

    /// Pixels per point, as ImageIO reads it: DPI over 72, and never below 1.
    public var scale: CGFloat {
        max(1, CGFloat(dpi ?? 72) / 72)
    }

    /// `data`, a PNG or JPEG without Shot's metadata, as libpng or libjpeg writes one, with `dpi` and `metadata` added
    /// where ImageIO puts them; `nil` when `data` isn't either.
    public static func adding(dpi: Double, metadata: ImageMetadata, to data: Data) -> Data? {
        PNGChunks.adding(dpi: dpi, metadata: metadata, to: data) ?? JPEGSegments.adding(dpi: dpi, metadata: metadata, to: data)
    }
}

extension ImageMetadata {
    /// Read from what a file's Exif user comment and XMP properties say.
    init(userComment: String?, property: (String) -> String?) {
        self.init(
            windowShadow: userComment == Self.windowShadowComment,
            record: property("record").flatMap { try? CaptureRecord.decoded(from: Data($0.utf8)) },
            projectID: property("project")
        )
    }

    /// The XMP properties to write, in Shot's namespace.
    var xmpProperties: [(name: String, value: String)] {
        var properties: [(name: String, value: String)] = []
        if let text = record.flatMap({ try? $0.encoded() }).flatMap({ String(data: $0, encoding: .utf8) }) {
            properties.append(("record", text))
        }
        if let projectID {
            properties.append(("project", projectID))
        }
        return properties
    }
}

/// Bounds-checked reads from encoded data, by offset from its start, which a slice of `Data` doesn't start at.
struct ByteReader {
    let data: Data
    var bigEndian = true

    var count: Int { data.count }

    func byte(_ offset: Int) -> Int? {
        offset >= 0 && offset < data.count ? Int(data[data.startIndex + offset]) : nil
    }

    func uint16(_ offset: Int) -> Int? {
        guard let a = byte(offset), let b = byte(offset + 1) else {
            return nil
        }
        return bigEndian ? a << 8 | b : b << 8 | a
    }

    func uint32(_ offset: Int) -> Int? {
        guard let a = uint16(offset), let b = uint16(offset + 2) else {
            return nil
        }
        return bigEndian ? a << 16 | b : b << 16 | a
    }

    func bytes(_ offset: Int, _ length: Int) -> Data? {
        guard offset >= 0, length >= 0, offset + length <= data.count else {
            return nil
        }
        return data[data.startIndex + offset ..< data.startIndex + offset + length]
    }

    func starts(with prefix: Data, at offset: Int = 0) -> Bool {
        bytes(offset, prefix.count).map { Data($0) == prefix } ?? false
    }
}

extension Data {
    /// `value` big-endian in `size` bytes.
    static func bigEndian(_ value: Int, size: Int) -> Data {
        Data((0 ..< size).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
}
