#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

/// Image helpers that need only CoreGraphics. ShotCoreApple adds the encoding and decoding, with ImageIO.
public enum ImageCodec {
    /// Resamples a Retina capture to 1 pixel per point, on a `canvasType` canvas.
    public static func downscaled(_ image: CGImage, scale: CGFloat, canvasType: any Canvas.Type) -> CGImage {
        guard scale > 1 else {
            return image
        }
        let width = Int((CGFloat(image.width) / scale).rounded()), height = Int((CGFloat(image.height) / scale).rounded())
        guard let canvas = canvasType.init(width: width, height: height, format: .matching(image)) else {
            return image
        }
        canvas.setInterpolation(.high)
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return canvas.makeImage() ?? image
    }
}

public enum ImageTrim {
    /// Crops away fully transparent rows and columns at the edges, reading them from a `canvasType` canvas.
    public static func trimTransparentEdges(_ image: CGImage, canvasType: any Canvas.Type) -> CGImage {
        let width = image.width, height = image.height
        guard let canvas = canvasType.init(width: width, height: height, format: .sRGB) else {
            return image
        }
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bounds = canvas.makeBitmap()?.visibleBounds else {
            return image
        }
        return image.cropping(to: bounds) ?? image
    }
}
#endif
