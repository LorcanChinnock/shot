import Foundation

/// Packs a screen cast's frames for ffmpeg, which reads raw video of one size: a recording keeps its first frame's size,
/// as the Mac's `SCStream` keeps one output size, so a frame of another size, from a resized window, is scaled into it.
public enum CastFrame {
    /// Whether a layout of `CPipeWireStream`'s `shot_pw_format`, numbered as `FFmpeg.castPixelFormats`, puts red first.
    public static func isRedFirst(_ format: Int) -> Bool {
        format >= 2
    }

    /// The `width` × `height` four-byte pixels at `pixels`, each row `stride` bytes on from the one before, packed into
    /// `size` with no gaps between rows: as they are when they're that size, or else scaled to fit, keeping their shape,
    /// each pixel the nearest, and centred on black. `swapsRedAndBlue` swaps the first and third byte of each pixel, for a
    /// frame whose layout has them the other way round from the first frame's.
    public static func packed(
        _ pixels: UnsafeRawPointer, width: Int, height: Int, stride: Int, into size: (width: Int, height: Int), swapsRedAndBlue: Bool = false
    ) -> Data {
        let row = size.width * 4
        if width == size.width, height == size.height, !swapsRedAndBlue {
            if stride == row {
                return Data(bytes: pixels, count: row * height)
            }
            var data = Data(count: row * height)
            data.withUnsafeMutableBytes { output in
                for y in 0 ..< height {
                    output.baseAddress!.advanced(by: y * row).copyMemory(from: pixels.advanced(by: y * stride), byteCount: row)
                }
            }
            return data
        }
        // The scale that fits the frame in, and where it lands.
        let scale = min(Double(size.width) / Double(width), Double(size.height) / Double(height))
        let fitted = (width: max(1, min(size.width, Int((Double(width) * scale).rounded()))), height: max(1, min(size.height, Int((Double(height) * scale).rounded()))))
        let left = (size.width - fitted.width) / 2, top = (size.height - fitted.height) / 2
        let columns = (0 ..< fitted.width).map { min(width - 1, Int((Double($0) + 0.5) * Double(width) / Double(fitted.width))) * 4 }
        var data = Data(count: row * size.height)
        data.withUnsafeMutableBytes { output in
            let bytes = output.bindMemory(to: UInt8.self)
            for y in 0 ..< fitted.height {
                let source = pixels.advanced(by: min(height - 1, Int((Double(y) + 0.5) * Double(height) / Double(fitted.height))) * stride)
                    .assumingMemoryBound(to: UInt8.self)
                var target = (top + y) * row + left * 4
                for column in columns {
                    bytes[target] = source[column + (swapsRedAndBlue ? 2 : 0)]
                    bytes[target + 1] = source[column + 1]
                    bytes[target + 2] = source[column + (swapsRedAndBlue ? 0 : 2)]
                    bytes[target + 3] = source[column + 3]
                    target += 4
                }
            }
        }
        return data
    }
}
