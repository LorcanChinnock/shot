import CoreGraphics

/// How a capture's picture fills a thumbnail: the gallery's tiles and the Quick Access card.
public enum ThumbnailFit {
    /// How many times wider than the frame, in shape, an image must be before it shows whole rather than filling the frame:
    /// past it, filling would show less than five-eighths of the image's width. Cropping a strip such as one row of a window to
    /// its middle can leave a blank thumbnail, so a strip that wide shows whole between empty bands instead (#1372). A tall
    /// image always fills: its top and bottom are cropped, but lines of text keep their full width and stay readable.
    public static let widestFilled: CGFloat = 1.6

    /// Whether `image` shows whole inside `frame`, rather than filling it and being cropped to its middle.
    public static func showsWhole(_ image: CGSize, in frame: CGSize) -> Bool {
        guard image.width > 0, image.height > 0, frame.width > 0, frame.height > 0 else {
            return false
        }
        return (image.width / image.height) / (frame.width / frame.height) > widestFilled
    }
}
