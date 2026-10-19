#if canImport(CoreGraphics)
import CoreGraphics

extension RGBA {
    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}
#endif
