#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

/// Writes a looping GIF a frame at a time through ShotModel's `GIFEncoder`, drawing each image into the RGBA pixels it
/// takes.
final class GIFStreamWriter {
    private let output: (Data) throws -> Void
    private var encoder: GIFEncoder?
    /// `Bitmap`'s layout, sRGB, so frames are compared, cropped and quantised in the colors the GIF stores.
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private var pixels: [UInt32] = []
    var bytesWritten: Int { encoder?.bytesWritten ?? 0 }

    init(output: @escaping (Data) throws -> Void) {
        self.output = output
    }

    /// Adds `image` for `delay` seconds; later frames are drawn at the first frame's size.
    func add(_ image: CGImage, delay: Double) throws {
        let encoder = encoder ?? GIFEncoder(width: image.width, height: image.height, output: output)
        if self.encoder == nil {
            self.encoder = encoder
            pixels = Array(repeating: 0, count: encoder.width * encoder.height)
        }
        try draw(image, width: encoder.width, height: encoder.height)
        try encoder.add(&pixels, delay: delay)
    }

    func finish() throws {
        guard let encoder else {
            throw GIFExporter.ExportError.finalizeFailed
        }
        try encoder.finish()
    }

    private func draw(_ image: CGImage, width: Int, height: Int) throws {
        try pixels.withUnsafeMutableBytes { pixels in
            guard let colorSpace, let context = CGContext(
                data: pixels.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw GIFExporter.ExportError.cannotCreateDestination
            }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
#endif
