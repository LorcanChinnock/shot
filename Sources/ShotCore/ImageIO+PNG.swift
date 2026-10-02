import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PNG {
    /// Encodes with DPI = 72 × scale so Retina captures open at point size.
    public static func data(from image: CGImage, scale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        let dpi = 72 * scale
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    public static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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
