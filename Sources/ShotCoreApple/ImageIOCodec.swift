import CoreGraphics
import Foundation

/// The Mac's `ImageCoding`: ImageIO, through `ImageCodec`.
public struct ImageIOCodec: ImageCoding {
    public init() {}

    public func encode(_ bitmap: Bitmap, as format: ImageFormat, quality: Double, metadata: ImageMetadata) -> Data? {
        bitmap.cgImage.flatMap { image in
            ImageCodec.data(from: image, scale: bitmap.scale, format: format, quality: quality, windowShadow: metadata.windowShadow, record: metadata.record, projectID: metadata.projectID)
        }
    }

    public func decode(_ data: Data) -> Bitmap? {
        ImageCodec.image(from: data).flatMap { Bitmap($0, scale: ImageCodec.scale(of: data)) }
    }

    public func decode(fileAt url: URL) -> Bitmap? {
        ImageCodec.image(at: url).flatMap { Bitmap($0, scale: ImageCodec.scale(ofFileAt: url)) }
    }

    public func info(ofFileAt url: URL) -> ImageFileInfo? {
        ImageCodec.info(ofFileAt: url)
    }

    public func info(of data: Data) -> ImageFileInfo? {
        ImageCodec.info(of: data)
    }

    public func scale(ofFileAt url: URL) -> CGFloat {
        ImageCodec.scale(ofFileAt: url)
    }

    public func record(ofFileAt url: URL) -> CaptureRecord? {
        ImageCodec.record(ofFileAt: url)
    }

    public func projectID(ofFileAt url: URL) -> String? {
        ImageCodec.projectID(ofFileAt: url)
    }

    public func hasWindowShadow(ofFileAt url: URL) -> Bool {
        ImageCodec.hasWindowShadow(ofFileAt: url)
    }

    public func previewJPEG(at url: URL, maxPixelSize: Int, maxBytes: Int) -> Data? {
        ImageCodec.previewJPEG(at: url, maxPixelSize: maxPixelSize, maxBytes: maxBytes)
    }

    public func data(from image: CGImage, scale: CGFloat, format: ImageFormat, metadata: ImageMetadata) -> Data? {
        ImageCodec.data(from: image, scale: scale, format: format, windowShadow: metadata.windowShadow, record: metadata.record, projectID: metadata.projectID)
    }

    public func image(at url: URL) -> CGImage? {
        ImageCodec.image(at: url)
    }

    public func image(from data: Data) -> CGImage? {
        ImageCodec.image(from: data)
    }

    public func previewJPEG(of image: CGImage, maxPixelSize: Int, maxBytes: Int) -> Data? {
        ImageCodec.previewJPEG(of: image, maxPixelSize: maxPixelSize, maxBytes: maxBytes)
    }

    /// At 72 DPI, with no metadata, as a placed image has always been saved in a project.
    public func png(from image: CGImage) -> Data? {
        ImageCodec.data(from: image, scale: 1)
    }

    public func image(fromPNG data: Data) -> CGImage? {
        ImageCodec.image(from: data)
    }
}

extension Bitmap {
    /// `image`'s pixels in sRGB. An image already laid out as a `Bitmap` is read as it is; any other is drawn into one.
    public init?(_ image: CGImage, scale: CGFloat = 1) {
        let width = image.width, height = image.height
        if image.bitsPerComponent == 8, image.bitsPerPixel == 32, image.bytesPerRow == width * 4, image.alphaInfo == .premultipliedLast,
           image.byteOrderInfo == .orderDefault || image.byteOrderInfo == .order32Big,
           image.colorSpace?.name == CGColorSpace.sRGB, let data = image.dataProvider?.data as Data? {
            self.init(width: width, height: height, scale: scale, pixels: data)
            return
        }
        var pixels = Data(count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }
        self.init(width: width, height: height, scale: scale, pixels: pixels)
    }

    /// The pixels as an sRGB image.
    public var cgImage: CGImage? {
        guard let provider = CGDataProvider(data: pixels as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
