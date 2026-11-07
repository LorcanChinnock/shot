import CoreGraphics
import Foundation

/// Where a pinned capture first appears: at its own size, shrunk to fit `fraction` of the screen with its aspect kept,
/// centred, and each further pin `cascade` points down and right of the last so none hides another.
/// Frames are in AppKit's bottom-left-origin screen coordinates.
public enum PinLayout {
    public static let fraction: CGFloat = 0.5
    public static let cascade: CGFloat = 28
    /// The shorter side never starts smaller than this, so a tiny capture still has room to grab.
    public static let minSide: CGFloat = 80

    /// The pin's size: `image` (in points) scaled down to fit `fraction` of `visible`, never up, but at least `minSide`
    /// on its shorter side, and never bigger than `visible`.
    public static func size(for image: CGSize, in visible: CGRect) -> CGSize {
        guard image.width > 0, image.height > 0 else {
            return CGSize(width: minSide, height: minSide)
        }
        let fit = min(1, visible.width * fraction / image.width, visible.height * fraction / image.height)
        let grow = max(1, minSide / (min(image.width, image.height) * fit))
        let cap = min(visible.width / (image.width * fit * grow), visible.height / (image.height * fit * grow), 1)
        let scale = fit * grow * cap
        return CGSize(width: (image.width * scale).rounded(), height: (image.height * scale).rounded())
    }

    /// How far the pin's bar sits in from the capture's left, right and top edges.
    public static let barInset: CGFloat = 6

    /// The strip across the top of a pin at `frame` that holds its bar, `barHeight` tall, with the inset above and below
    /// it. While the pin lets clicks through, clicks in this strip still reach the bar. Never taller than the pin.
    public static func barStrip(in frame: CGRect, barHeight: CGFloat) -> CGRect {
        let height = min(frame.height, max(0, barHeight) + barInset * 2)
        return CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
    }

    /// The pin's frame, `index` being how many pins are already open; the cascade wraps before leaving `visible`.
    public static func initialFrame(for image: CGSize, in visible: CGRect, index: Int) -> CGRect {
        let size = size(for: image, in: visible)
        let centred = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        let room = max(0, min(visible.maxX - (centred.x + size.width), centred.y - visible.minY))
        let steps = max(1, Int(room / cascade) + 1)
        let offset = CGFloat(max(0, index) % steps) * cascade
        return CGRect(x: (centred.x + offset).rounded(), y: (centred.y - offset).rounded(), width: size.width, height: size.height)
    }
}
