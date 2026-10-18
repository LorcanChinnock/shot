import CoreGraphics
import Foundation
@testable import ShotCore

// The CGContexts ShotCore made outside `Canvas` before #717 moved them onto `Canvas` and `Bitmap`, copied unchanged but
// for their names, for `ContextsGoldenTests`. They go in #717's PR 2.

enum LegacyContexts {
    // From `AnnotationFrame` and `StyleThumbnail`.
    static let placeholder: CGImage = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    // From `ImageCodec.downscaled`.
    static func downscaled(_ image: CGImage, scale: CGFloat) -> CGImage {
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

    // From `ImageTrim.trimTransparentEdges`.
    static func trimTransparentEdges(_ image: CGImage) -> CGImage {
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

    // From `ShotCommands.pixels`.
    static func pixels(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }

    // From `ShotCommands.highlight`.
    static func highlight(_ image: CGImage, mask: [UInt8], regions: [ImageDiff.Region], lineWidth: CGFloat) -> CGImage? {
        let width = image.width, height = image.height
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let alpha = Data(mask.map { $0 == 0 ? 0 : 255 })
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let provider = CGDataProvider(data: alpha as CFData),
              let changed = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            return nil
        }
        let red = RGBA.presets[0]
        context.draw(image, in: bounds)
        context.setFillColor(CGColor(gray: 0, alpha: 0.6))
        context.fill(bounds)
        context.saveGState()
        context.clip(to: bounds, mask: changed)
        context.draw(image, in: bounds)
        context.setFillColor(RGBA(red.r, red.g, red.b, 0.45).cgColor)
        context.fill(bounds)
        context.restoreGState()
        context.setStrokeColor(red.cgColor)
        context.setLineWidth(lineWidth)
        for region in regions {
            // Top-left origin to the context's bottom-left, just outside the changed pixels so the box doesn't cover them.
            let rect = CGRect(x: region.x, y: height - region.y - region.height, width: region.width, height: region.height)
            context.stroke(rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2))
        }
        return context.makeImage()
    }
}
