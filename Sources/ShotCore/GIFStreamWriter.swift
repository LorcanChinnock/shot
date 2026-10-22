import CoreGraphics
import Foundation

/// Writes a looping GIF a frame at a time through `GIFEncoder`, drawing each image into a bitmap context for the RGBA
/// pixels it takes.
package final class GIFStreamWriter {
    private let output: (Data) throws -> Void
    private var encoder: GIFEncoder?
    private var pixels: [UInt32] = []
    var bytesWritten: Int { encoder?.bytesWritten ?? 0 }

    package init(output: @escaping (Data) throws -> Void) {
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

    /// Read as a `Bitmap`, sRGB, so frames are compared, cropped and quantised in the colors the GIF stores.
    private func draw(_ image: CGImage, width: Int, height: Int) throws {
        guard let canvas = CGContext.bitmap(width: width, height: height, format: .sRGB) else {
            throw GIFExporter.ExportError.cannotCreateDestination
        }
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bitmap = canvas.makeBitmap() else {
            throw GIFExporter.ExportError.cannotCreateDestination
        }
        pixels.withUnsafeMutableBytes { pixels in
            _ = bitmap.pixels.copyBytes(to: pixels)
        }
    }
}
