import Foundation
@testable import ShotCore

// Stand-ins for the platform's canvas, codec and video, for tests of code that takes them but doesn't get as far as
// drawing, coding or reading video. They draw and write nothing and throw where they can, and the codec reads every
// file as its `image`.

final class UnusedCanvas: Canvas {
    init?(width: Int, height: Int, format: CanvasFormat) {
        nil
    }

    static var effects: any ImageEffects { preconditionFailure("no effects") }
    static var shaper: any TextShaper { preconditionFailure("no shaper") }

    func saveState() {}
    func restoreState() {}
    func translateBy(x: CGFloat, y: CGFloat) {}
    func scaleBy(x: CGFloat, y: CGFloat) {}
    func rotate(by angle: CGFloat) {}
    var pixelScale: CGFloat { 1 }
    var clipBounds: CGRect { .infinite }
    func clip(to rect: CGRect) {}
    func clip(to path: CanvasPath) {}
    func setFillColor(_ color: RGBA) {}
    func setStrokeColor(_ color: RGBA) {}
    func setLineWidth(_ width: CGFloat) {}
    func setLineCap(_ cap: CanvasLineCap) {}
    func setLineJoin(_ join: CanvasLineJoin) {}
    func setBlendMode(_ mode: CanvasBlendMode) {}
    func setAlpha(_ alpha: CGFloat) {}
    func setInterpolation(_ quality: CanvasInterpolation) {}
    func setShadow(offset: CGSize, blur: CGFloat, color: RGBA) {}
    func beginTransparencyLayer() {}
    func endTransparencyLayer() {}
    func fill(_ rect: CGRect) {}
    func fill(_ path: CanvasPath) {}
    func stroke(_ path: CanvasPath) {}
    func draw(_ line: any ShapedLine, at position: CGPoint, outlined: Bool) {}
    func makeBitmap() -> Bitmap? { nil }
    func draw(_ image: PlatformImage, in rect: CGRect) {}
    func clip(to rect: CGRect, mask: PlatformImage) {}
    func makeImage() -> PlatformImage? { nil }
}

struct StandInCodec: ImageCoding {
    var image: PlatformImage?

    func encode(_ bitmap: Bitmap, as format: ImageFormat, quality: Double, metadata: ImageMetadata) -> Data? { nil }
    func decode(_ data: Data) -> Bitmap? { nil }
    func decode(fileAt url: URL) -> Bitmap? { nil }
    func info(ofFileAt url: URL) -> ImageFileInfo? { nil }
    func info(of data: Data) -> ImageFileInfo? { nil }
    func scale(ofFileAt url: URL) -> CGFloat { 1 }
    func record(ofFileAt url: URL) -> CaptureRecord? { nil }
    func projectID(ofFileAt url: URL) -> String? { nil }
    func hasWindowShadow(ofFileAt url: URL) -> Bool { false }
    func previewJPEG(at url: URL, maxPixelSize: Int, maxBytes: Int) -> Data? { nil }
    func data(from image: PlatformImage, scale: CGFloat, format: ImageFormat, metadata: ImageMetadata) -> Data? { nil }
    func image(at url: URL) -> PlatformImage? { image }
    func image(from data: Data) -> PlatformImage? { image }
    func previewJPEG(of image: PlatformImage, maxPixelSize: Int, maxBytes: Int) -> Data? { nil }
    func png(from image: PlatformImage) -> Data? { nil }
    func image(fromPNG data: Data) -> PlatformImage? { image }
}
