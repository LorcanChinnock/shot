import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes and decodes captures as PNG or JPEG, preserving the Retina scale as DPI.
public enum ImageCodec {
    /// What a window capture that includes the macOS window shadow says in its Exif comment, so the editor opened on it
    /// later knows not to offer a second shadow.
    static let windowShadowMarker = "Shot: includes the macOS window shadow"

    /// The XMP namespace of `record`, and the property it's stored in as JSON text.
    static let recordNamespace = "https://shot.lorcanchinnock.com/ns/capture/1.0/"
    static let recordPath = "shot:record"

    /// Encodes with DPI = 72 × scale so Retina captures open at point size. `windowShadow` marks a window capture that
    /// includes the macOS window shadow. `record`, for agents, goes in the file's XMP, written in the same pass: copying
    /// the image again with metadata added would be cheaper, but ImageIO then empties a PNG's Exif comment.
    public static func data(from image: CGImage, scale: CGFloat, format: ImageFormat = .png, windowShadow: Bool = false, record: CaptureRecord? = nil) -> Data? {
        let data = NSMutableData()
        let type = format == .png ? UTType.png : UTType.jpeg
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let dpi = 72 * scale
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        if windowShadow {
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: windowShadowMarker]
        }
        if let metadata = record.flatMap(metadata) {
            CGImageDestinationAddImageAndMetadata(destination, image, metadata, properties as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private static func metadata(for record: CaptureRecord) -> CGImageMetadata? {
        let metadata = CGImageMetadataCreateMutable()
        guard let json = try? record.encoded(), let text = String(data: json, encoding: .utf8),
              CGImageMetadataRegisterNamespaceForPrefix(metadata, recordNamespace as CFString, "shot" as CFString, nil),
              CGImageMetadataSetValueWithPath(metadata, nil, recordPath as CFString, text as CFString)
        else {
            return nil
        }
        return metadata
    }

    /// The record Shot wrote in the image file at `url`, or `nil` when it has none or isn't an image.
    public static func record(ofFileAt url: URL) -> CaptureRecord? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(record)
    }

    public static func record(of data: Data) -> CaptureRecord? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(record)
    }

    private static func record(_ source: CGImageSource) -> CaptureRecord? {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tag = CGImageMetadataCopyTagWithPath(metadata, nil, recordPath as CFString),
              let text = CGImageMetadataTagCopyValue(tag) as? String
        else {
            return nil
        }
        return try? CaptureRecord.decoded(from: Data(text.utf8))
    }

    /// Resamples a Retina capture to 1 pixel per point.
    public static func downscaled(_ image: CGImage, scale: CGFloat) -> CGImage {
        guard scale > 1 else {
            return image
        }
        let width = Int((CGFloat(image.width) / scale).rounded()), height = Int((CGFloat(image.height) / scale).rounded())
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    /// An independent bitmap at most `maxPixelSize` on its long edge, decoded from encoded image data.
    public static func thumbnail(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A JPEG of the image file at `url` for an AI agent: at most `maxPixelSize` on its long edge, never enlarged, and
    /// at most `maxBytes`, lowering the quality and then halving the size until it fits. 1568 pixels is what vision
    /// models scale to anyway. Transparency, such as a window shadow, goes white, since JPEG has none.
    public static func previewJPEG(at url: URL, maxPixelSize: Int = 1568, maxBytes: Int = 1_000_000) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return previewJPEG(of: source, maxPixelSize: maxPixelSize, maxBytes: maxBytes)
    }

    /// `previewJPEG(at:)` for an image already in memory, such as a video's poster frame.
    public static func previewJPEG(of image: CGImage, maxPixelSize: Int = 1568, maxBytes: Int = 1_000_000) -> Data? {
        guard let png = data(from: image, scale: 1), let source = CGImageSourceCreateWithData(png as CFData, nil) else {
            return nil
        }
        return previewJPEG(of: source, maxPixelSize: maxPixelSize, maxBytes: maxBytes)
    }

    private static func previewJPEG(of source: CGImageSource, maxPixelSize: Int, maxBytes: Int) -> Data? {
        var size = maxPixelSize
        while size >= 16 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let ctx = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else {
                return nil
            }
            let bounds = CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(bounds)
            ctx.draw(thumbnail, in: bounds)
            guard let opaque = ctx.makeImage() else {
                return nil
            }
            for quality in [0.85, 0.7, 0.55, 0.4] {
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
                    return nil
                }
                CGImageDestinationAddImage(destination, opaque, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                if CGImageDestinationFinalize(destination), data.length <= maxBytes {
                    return data as Data
                }
            }
            // Halve what it is, not what was asked for, or a small image would take several rounds to shrink at all.
            size = min(size, max(thumbnail.width, thumbnail.height)) / 2
        }
        return nil
    }

    public static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Decodes the first image in `data` now, so it doesn't decode again each time it's drawn.
    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    public static func scale(of data: Data) -> CGFloat {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return 1
        }
        return scale(of: source)
    }

    public static func scale(ofFileAt url: URL) -> CGFloat {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return 1
        }
        return scale(of: source)
    }

    /// Whether the image file at `url` is a window capture that includes the macOS window shadow.
    public static func hasWindowShadow(ofFileAt url: URL) -> Bool {
        CGImageSourceCreateWithURL(url as CFURL, nil).map(hasWindowShadow) ?? false
    }

    public static func hasWindowShadow(of data: Data) -> Bool {
        CGImageSourceCreateWithData(data as CFData, nil).map(hasWindowShadow) ?? false
    }

    private static func hasWindowShadow(_ source: CGImageSource) -> Bool {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        return exif?[kCGImagePropertyExifUserComment] as? String == windowShadowMarker
    }

    private static func scale(of source: CGImageSource) -> CGFloat {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        return max(1, CGFloat(dpi) / 72)
    }
}

public enum ImageTrim {
    /// Crops away fully transparent rows and columns at the edges.
    public static func trimTransparentEdges(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = ctx.data
        else {
            return image
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let alpha = data.assumingMemoryBound(to: UInt8.self)
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            let row = alpha + y * width
            for x in 0..<width where row[x] != 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            return image
        }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? image
    }
}
