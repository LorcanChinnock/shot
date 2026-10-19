import Foundation

#if !canImport(CoreGraphics)
/// CoreGraphics' vector, which Linux Foundation lacks. It codes as `[dx, dy]`, as Darwin's does, so a file saved on one
/// opens on the other.
public struct CGVector: Hashable, Sendable, Codable {
    public var dx: CGFloat
    public var dy: CGFloat

    public static let zero = CGVector()

    public init() {
        self.init(dx: 0, dy: 0)
    }

    public init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        dx = try container.decode(CGFloat.self)
        dy = try container.decode(CGFloat.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(dx)
        try container.encode(dy)
    }
}
#endif
