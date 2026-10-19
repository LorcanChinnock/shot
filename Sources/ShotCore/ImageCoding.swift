import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What Shot writes in an image file besides its pixels and scale, so it can read it back later, on any platform.
public struct ImageMetadata: Equatable, Sendable {
    /// A window capture that includes the macOS window shadow, so the editor opened on it later doesn't offer a second.
    public var windowShadow: Bool
    /// What was captured and marked, for agents.
    public var record: CaptureRecord?
    /// The ID of the file's project in `ProjectStore`.
    public var projectID: String?

    public init(windowShadow: Bool = false, record: CaptureRecord? = nil, projectID: String? = nil) {
        self.windowShadow = windowShadow
        self.record = record
        self.projectID = projectID
    }
}

/// What an image file is, read without decoding its pixels.
public struct ImageFileInfo: Equatable, Sendable {
    public var isGIF: Bool
    public var frames: Int
    /// `nil` when the file doesn't say.
    public var size: CaptureRecord.Size?

    public init(isGIF: Bool, frames: Int, size: CaptureRecord.Size?) {
        self.isGIF = isGIF
        self.frames = frames
        self.size = size
    }
}

/// Reads and writes image files: PNG and JPEG, plus whatever else the platform decodes, such as HEIC and GIF on a Mac.
/// The scale goes in the file as its DPI, 72 × scale, so a Retina capture opens at point size, and `ImageMetadata` goes
/// with it. It also codes the images a project or a copied annotation holds (`PNGCoding`). ShotCoreApple's `ImageIOCodec`
/// is the Mac's; ShotCore code takes one as `codec`.
public protocol ImageCoding: PNGCoding {
    /// PNG, or JPEG at `quality` from 0 to 1.
    func encode(_ bitmap: Bitmap, as format: ImageFormat, quality: Double, metadata: ImageMetadata) -> Data?
    /// The first image in `data`, at the scale its DPI gives.
    func decode(_ data: Data) -> Bitmap?
    func decode(fileAt url: URL) -> Bitmap?

    /// `nil` when the file isn't an image.
    func info(ofFileAt url: URL) -> ImageFileInfo?
    func info(of data: Data) -> ImageFileInfo?
    /// 1 when the file isn't an image or doesn't say.
    func scale(ofFileAt url: URL) -> CGFloat
    func record(ofFileAt url: URL) -> CaptureRecord?
    func projectID(ofFileAt url: URL) -> String?
    func hasWindowShadow(ofFileAt url: URL) -> Bool

    /// A JPEG of the image file at `url` for an AI agent: at most `maxPixelSize` on its long edge, never enlarged, and
    /// at most `maxBytes`. Transparency goes white, since JPEG has none.
    func previewJPEG(at url: URL, maxPixelSize: Int, maxBytes: Int) -> Data?

    #if canImport(CoreGraphics)
    // The same for the images a document holds and a canvas makes, which are `PlatformImage`s, so CGImages on a Mac. They
    // keep the image's own colour space, such as Display P3, which a `Bitmap` in sRGB would lose.
    func data(from image: CGImage, scale: CGFloat, format: ImageFormat, metadata: ImageMetadata) -> Data?
    func image(at url: URL) -> CGImage?
    /// Decoded now, so it doesn't decode again each time it's drawn.
    func image(from data: Data) -> CGImage?
    func previewJPEG(of image: CGImage, maxPixelSize: Int, maxBytes: Int) -> Data?
    #endif
}

extension ImageCoding {
    /// 1568 pixels is what vision models scale to anyway.
    public func previewJPEG(at url: URL) -> Data? {
        previewJPEG(at: url, maxPixelSize: 1568, maxBytes: 1_000_000)
    }

    #if canImport(CoreGraphics)
    public func data(from image: CGImage, scale: CGFloat, format: ImageFormat = .png) -> Data? {
        data(from: image, scale: scale, format: format, metadata: ImageMetadata())
    }

    public func previewJPEG(of image: CGImage) -> Data? {
        previewJPEG(of: image, maxPixelSize: 1568, maxBytes: 1_000_000)
    }
    #endif
}
