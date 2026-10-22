import CoreGraphics
import Foundation

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
