#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import ShotModel

enum AffineStep: Sendable {
    case translate(CGFloat, CGFloat)
    case scale(CGFloat, CGFloat)
    case rotate(CGFloat)
}

struct AffineCase: Sendable, CustomTestStringConvertible {
    let name: String
    let steps: [AffineStep]
    let matrix: [CGFloat]
    let rect: CGRect

    var testDescription: String { name }
}

private let source = CGRect(x: 1, y: 2, width: 10, height: 20)

// Linux has no CoreGraphics to compare with, so it checks these, which are what Darwin gives.
private let cases = [
    AffineCase(name: "identity", steps: [], matrix: [1, 0, 0, 1, 0, 0], rect: source),
    AffineCase(name: "translate", steps: [.translate(3, -4)], matrix: [1, 0, 0, 1, 3, -4], rect: CGRect(x: 4, y: -2, width: 10, height: 20)),
    AffineCase(name: "scale", steps: [.scale(2, 0.5)], matrix: [2, 0, 0, 0.5, 0, 0], rect: CGRect(x: 2, y: 1, width: 20, height: 10)),
    AffineCase(name: "rotate", steps: [.rotate(.pi / 2)], matrix: [0, 1, -1, 0, 0, 0], rect: CGRect(x: -22, y: 1, width: 20, height: 10)),
    AffineCase(
        name: "concatenation", steps: [.translate(-5, -10), .scale(2, 2), .rotate(.pi / 2), .translate(100, 50)],
        matrix: [0, 2, -2, 0, 120, 40], rect: CGRect(x: 76, y: 42, width: 40, height: 20)
    ),
]

private func portable(_ steps: [AffineStep]) -> PortableAffineTransform {
    steps.reduce(.identity) { transform, step in
        switch step {
        case let .translate(x, y): transform.concatenating(PortableAffineTransform(translationX: x, y: y))
        case let .scale(x, y): transform.concatenating(PortableAffineTransform(scaleX: x, y: y))
        case let .rotate(angle): transform.concatenating(PortableAffineTransform(rotationAngle: angle))
        }
    }
}

private func components(_ t: PortableAffineTransform) -> [CGFloat] {
    [t.a, t.b, t.c, t.d, t.tx, t.ty]
}

private func isClose(_ lhs: [CGFloat], _ rhs: [CGFloat]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1) < 1e-12 }
}

private func isClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    isClose([lhs.minX, lhs.minY, lhs.width, lhs.height], [rhs.minX, rhs.minY, rhs.width, rhs.height])
}

@Test(arguments: cases)
func theAffineShimMatchesDarwin(_ test: AffineCase) {
    let transform = portable(test.steps)
    #expect(isClose(components(transform), test.matrix))
    #expect(isClose(transform.boundingBox(of: source), test.rect))
    #if canImport(CoreGraphics)
    let darwin = test.steps.reduce(CGAffineTransform.identity) { transform, step in
        switch step {
        case let .translate(x, y): transform.concatenating(CGAffineTransform(translationX: x, y: y))
        case let .scale(x, y): transform.concatenating(CGAffineTransform(scaleX: x, y: y))
        case let .rotate(angle): transform.concatenating(CGAffineTransform(rotationAngle: angle))
        }
    }
    #expect(components(transform) == [darwin.a, darwin.b, darwin.c, darwin.d, darwin.tx, darwin.ty])
    #expect(transform.boundingBox(of: source) == source.applying(darwin))
    #endif
}

@Test func aNullRectStaysNullThroughATransform() {
    #expect(PortableAffineTransform(translationX: 3, y: 4).boundingBox(of: .null).isNull)
}
