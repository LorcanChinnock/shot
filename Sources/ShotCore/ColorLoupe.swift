import CoreGraphics

/// Pick Colour's loupe (Capture › Permission card, colour loupe…): a round grid of the device pixels round the pointer,
/// centred on it, with a label giving the middle pixel's colour and a hint below. The pixel maths are `Loupe`'s, which the
/// area overlay's magnifier shares.
public enum ColorLoupe {
    /// The loupe's diameter at the default text size, before it's fitted to whole-point cells.
    public static let side: CGFloat = 120
    /// Between the loupe's rings, the label and the hint.
    public static let gap: CGFloat = 10
    /// The least room kept between the label or hint and the screen's edge.
    static let margin: CGFloat = 8

    /// Each cell's width in whole points, so the grid lines land on the same pixels in every row; at least 1.
    public static func cell(side: CGFloat) -> CGFloat {
        max(1, (side / CGFloat(Loupe.cells)).rounded())
    }

    /// Where the loupe, the label and the hint go, in view space (points, y up). The loupe is centred on the pointer, so its
    /// middle cell is the pixel that would be picked, and can run off the screen's edge as the pointer nears it. The label
    /// and hint sit below it, `gap` apart, or above it when there's no room below, each centred under the pointer and kept
    /// `margin` inside `bounds`. `outset` is how far the loupe's rings reach beyond its frame.
    public static func layout(pointer: CGPoint, side: CGFloat, outset: CGFloat, label: CGSize, hint: CGSize, in bounds: CGRect) -> (loupe: CGRect, label: CGRect, hint: CGRect) {
        let loupe = CGRect(x: (pointer.x - side / 2).rounded(), y: (pointer.y - side / 2).rounded(), width: side, height: side)
        let below = loupe.minY - outset - gap
        let stack = label.height + gap + hint.height
        let fitsBelow = below - stack >= bounds.minY + margin
        let labelY = fitsBelow ? below - label.height : loupe.maxY + outset + gap + hint.height + gap
        let hintY = fitsBelow ? labelY - gap - hint.height : loupe.maxY + outset + gap
        func centred(_ size: CGSize, y: CGFloat) -> CGRect {
            let room = bounds.insetBy(dx: margin, dy: 0)
            var x = (pointer.x - size.width / 2).rounded()
            x = min(max(x, room.minX), room.maxX - size.width)
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }
        return (loupe, centred(label, y: labelY), centred(hint, y: hintY))
    }
}

/// One pixel of a captured image as sRGB, the space Shot's hex values are in.
public enum PixelColor {
    /// The colour of the device pixel at `x`, `y`, counted from the image's top-left corner, converted from the image's own
    /// colour space (a display's, often Display P3) to sRGB. Nil when the pixel lies off the image.
    public static func sRGB(of image: CGImage, x: Int, y: Int) -> RGBA? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else {
            return nil
        }
        let alpha = CGFloat(bytes[3]) / 255
        guard alpha > 0 else {
            return RGBA(0, 0, 0, 0)
        }
        // Undo the premultiplication, so a translucent pixel keeps its own colour.
        func channel(_ value: UInt8) -> CGFloat { min(CGFloat(value) / 255 / alpha, 1) }
        return RGBA(channel(bytes[0]), channel(bytes[1]), channel(bytes[2]), alpha)
    }
}
