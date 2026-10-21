import Foundation

/// CoreGraphics' affine transform, which Linux Foundation lacks: `CGAffineTransform` there. It's built on every
/// platform so the tests can check it against Darwin's, but only Linux names it `CGAffineTransform`.
public struct PortableAffineTransform: Equatable, Sendable {
    public var a: CGFloat
    public var b: CGFloat
    public var c: CGFloat
    public var d: CGFloat
    public var tx: CGFloat
    public var ty: CGFloat

    public static let identity = PortableAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public init(translationX tx: CGFloat, y ty: CGFloat) {
        self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty)
    }

    public init(scaleX sx: CGFloat, y sy: CGFloat) {
        self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    public init(rotationAngle angle: CGFloat) {
        let sine = sin(angle)
        let cosine = cos(angle)
        self.init(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }

    /// This transform, then `other`.
    public func concatenating(_ other: PortableAffineTransform) -> PortableAffineTransform {
        PortableAffineTransform(
            a: a * other.a + b * other.c,
            b: a * other.b + b * other.d,
            c: c * other.a + d * other.c,
            d: c * other.b + d * other.d,
            tx: tx * other.a + ty * other.c + other.tx,
            ty: tx * other.b + ty * other.d + other.ty
        )
    }

    /// The smallest rect holding `rect`'s four corners once transformed, as `CGRect.applying` gives.
    public func boundingBox(of rect: CGRect) -> CGRect {
        guard !rect.isNull else {
            return rect
        }
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ].map { CGPoint(x: a * $0.x + c * $0.y + tx, y: b * $0.x + d * $0.y + ty) }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let minX = xs.min()!
        let minY = ys.min()!
        return CGRect(x: minX, y: minY, width: xs.max()! - minX, height: ys.max()! - minY)
    }
}

#if !canImport(CoreGraphics)
public typealias CGAffineTransform = PortableAffineTransform

extension CGRect {
    public func applying(_ transform: CGAffineTransform) -> CGRect {
        transform.boundingBox(of: self)
    }
}
#endif
