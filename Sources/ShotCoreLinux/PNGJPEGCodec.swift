import CPNG
import CTurboJPEG
import Foundation

/// Linux's `ImageCoding`: PNG through libpng and JPEG through libjpeg-turbo, with the scale and `ImageMetadata` where
/// ImageIO puts them (`ImageHeader`), so a file goes either way between Linux and a Mac. It uses libpng's simplified API
/// and the TurboJPEG API, which return their errors, since the classic APIs report them with a `longjmp` Swift can't
/// catch. Other formats, such as HEIC and GIF, don't decode.
public struct PNGJPEGCodec: ImageCoding {
    public init() {}

    public func encode(_ bitmap: Bitmap, as format: ImageFormat, quality: Double, metadata: ImageMetadata) -> Data? {
        let encoded = format == .png ? png(bitmap) : jpeg(bitmap, quality: quality)
        return encoded.flatMap { ImageHeader.adding(dpi: 72 * bitmap.scale, metadata: metadata, to: $0) }
    }

    public func decode(_ data: Data) -> Bitmap? {
        guard let header = ImageHeader(data),
              let pixels = header.format == .png ? pngPixels(data, width: header.width, height: header.height) : jpegPixels(data, width: header.width, height: header.height)
        else {
            return nil
        }
        return Bitmap(width: header.width, height: header.height, scale: header.scale, pixels: pixels)
    }

    public func decode(fileAt url: URL) -> Bitmap? {
        contents(of: url).flatMap(decode)
    }

    public func info(ofFileAt url: URL) -> ImageFileInfo? {
        contents(of: url).flatMap(info)
    }

    public func info(of data: Data) -> ImageFileInfo? {
        ImageHeader(data).map { ImageFileInfo(isGIF: false, frames: 1, size: CaptureRecord.Size(width: $0.width, height: $0.height)) }
    }

    public func scale(ofFileAt url: URL) -> CGFloat {
        header(ofFileAt: url)?.scale ?? 1
    }

    public func record(ofFileAt url: URL) -> CaptureRecord? {
        header(ofFileAt: url)?.metadata.record
    }

    public func projectID(ofFileAt url: URL) -> String? {
        header(ofFileAt: url)?.metadata.projectID
    }

    public func hasWindowShadow(ofFileAt url: URL) -> Bool {
        header(ofFileAt: url)?.metadata.windowShadow ?? false
    }

    public func previewJPEG(at url: URL, maxPixelSize: Int, maxBytes: Int) -> Data? {
        decode(fileAt: url).flatMap { preview(of: $0, maxPixelSize: maxPixelSize, maxBytes: maxBytes) }
    }

    public func data(from image: PlatformImage, scale: CGFloat, format: ImageFormat, metadata: ImageMetadata) -> Data? {
        Bitmap(width: image.width, height: image.height, scale: scale, pixels: image.bitmap.pixels).flatMap {
            encode($0, as: format, quality: 0.9, metadata: metadata)
        }
    }

    public func image(at url: URL) -> PlatformImage? {
        decode(fileAt: url).map(BitmapImage.init)
    }

    public func image(from data: Data) -> PlatformImage? {
        decode(data).map(BitmapImage.init)
    }

    public func previewJPEG(of image: PlatformImage, maxPixelSize: Int, maxBytes: Int) -> Data? {
        preview(of: image.bitmap, maxPixelSize: maxPixelSize, maxBytes: maxBytes)
    }

    /// At 72 DPI, with no metadata, as the Mac saves a placed image in a project.
    public func png(from image: PlatformImage) -> Data? {
        data(from: image, scale: 1, format: .png, metadata: ImageMetadata())
    }

    public func image(fromPNG data: Data) -> PlatformImage? {
        image(from: data)
    }

    // MARK: Files

    private func contents(of url: URL) -> Data? {
        try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func header(ofFileAt url: URL) -> ImageHeader? {
        contents(of: url).flatMap(ImageHeader.init)
    }

    /// As the Mac makes one: lowering the quality and then halving the size until it fits in `maxBytes`.
    private func preview(of bitmap: Bitmap, maxPixelSize: Int, maxBytes: Int) -> Data? {
        var size = maxPixelSize
        while size >= 16 {
            let thumbnail = bitmap.scaledDown(toFit: size).overWhite
            for quality in [0.85, 0.7, 0.55, 0.4] {
                guard let data = jpeg(thumbnail, quality: quality) else {
                    return nil
                }
                if data.count <= maxBytes {
                    return data
                }
            }
            // Halve what it is, not what was asked for, or a small image would take several rounds to shrink at all.
            size = min(size, max(thumbnail.width, thumbnail.height)) / 2
        }
        return nil
    }

    // MARK: PNG

    private func pngImage(width: Int, height: Int) -> png_image {
        var image = png_image()
        image.version = UInt32(PNG_IMAGE_VERSION)
        image.width = UInt32(width)
        image.height = UInt32(height)
        image.format = shot_png_format_rgba
        return image
    }

    /// PNG keeps straight alpha, so the pixels are unpremultiplied first.
    private func png(_ bitmap: Bitmap) -> Data? {
        var image = pngImage(width: bitmap.width, height: bitmap.height)
        let straight = Self.unpremultiplied(bitmap.pixels)
        // Room for the pixels stored, so the second attempt is only for an image that compresses worse than that.
        var size = png_alloc_size_t(bitmap.height * (bitmap.bytesPerRow + 1) + 1024)
        for _ in 0 ..< 2 {
            var output = Data(count: Int(size))
            let written = output.withUnsafeMutableBytes { buffer in
                straight.withUnsafeBytes { png_image_write_to_memory(&image, buffer.baseAddress, &size, 0, $0.baseAddress, 0, nil) }
            }
            if written != 0 {
                return output.prefix(Int(size))
            }
            guard size > output.count else {
                return nil
            }
        }
        return nil
    }

    private func pngPixels(_ data: Data, width: Int, height: Int) -> Data? {
        var image = png_image()
        image.version = UInt32(PNG_IMAGE_VERSION)
        let pixels = data.withUnsafeBytes { buffer -> Data? in
            guard png_image_begin_read_from_memory(&image, buffer.baseAddress, buffer.count) != 0 else {
                return nil
            }
            guard Int(image.width) == width, Int(image.height) == height else {
                png_image_free(&image)
                return nil
            }
            image.format = shot_png_format_rgba
            var pixels = Data(count: width * height * 4)
            let read = pixels.withUnsafeMutableBytes { png_image_finish_read(&image, nil, $0.baseAddress, 0, nil) }
            return read != 0 ? pixels : nil
        }
        return pixels.map(Self.premultiplied)
    }

    static func premultiplied(_ pixels: Data) -> Data {
        var bytes = [UInt8](pixels)
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] < 255 {
            let alpha = Int(bytes[i + 3])
            for channel in i ..< i + 3 {
                bytes[channel] = UInt8((Int(bytes[channel]) * alpha + 127) / 255)
            }
        }
        return Data(bytes)
    }

    static func unpremultiplied(_ pixels: Data) -> Data {
        var bytes = [UInt8](pixels)
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] < 255 {
            let alpha = Int(bytes[i + 3])
            for channel in i ..< i + 3 {
                bytes[channel] = alpha == 0 ? 0 : UInt8(min(255, (Int(bytes[channel]) * 255 + alpha / 2) / alpha))
            }
        }
        return Data(bytes)
    }

    // MARK: JPEG

    /// JPEG has no alpha, so the premultiplied colours are kept as they are, as if over black. Chroma is halved both
    /// ways, as ImageIO does.
    private func jpeg(_ bitmap: Bitmap, quality: Double) -> Data? {
        guard let handle = tjInitCompress() else {
            return nil
        }
        defer { tjDestroy(handle) }
        var output: UnsafeMutablePointer<UInt8>?
        var size: UInt = 0
        defer { tjFree(output) }
        let result = bitmap.pixels.withUnsafeBytes { buffer in
            tjCompress2(
                handle, buffer.bindMemory(to: UInt8.self).baseAddress, Int32(bitmap.width), 0, Int32(bitmap.height), Int32(TJPF_RGBX.rawValue),
                &output, &size, Int32(TJSAMP_420.rawValue), Int32(min(100, max(1, (quality * 100).rounded()))), 0
            )
        }
        guard result == 0, let output else {
            return nil
        }
        return Data(bytes: output, count: Int(size))
    }

    /// A JPEG is opaque, so its pixels are premultiplied as they come.
    private func jpegPixels(_ data: Data, width: Int, height: Int) -> Data? {
        guard let handle = tjInitDecompress() else {
            return nil
        }
        defer { tjDestroy(handle) }
        var pixels = Data(count: width * height * 4)
        let result = data.withUnsafeBytes { buffer in
            pixels.withUnsafeMutableBytes { output in
                tjDecompress2(
                    handle, buffer.bindMemory(to: UInt8.self).baseAddress, UInt(buffer.count), output.bindMemory(to: UInt8.self).baseAddress,
                    Int32(width), 0, Int32(height), Int32(TJPF_RGBA.rawValue), 0
                )
            }
        }
        // A warning, such as for a file cut short, still gives what it could read, as ImageIO does.
        return result == 0 || tjGetErrorCode(handle) == Int32(TJERR_WARNING.rawValue) ? pixels : nil
    }
}
