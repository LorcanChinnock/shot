import Foundation
import Testing
@testable import ShotCore

// On Linux this is ShotModel's CGVector; on macOS it's CoreGraphics', which the saved format has to match.
@Test func aVectorCodesAsDxThenDy() throws {
    let data = try JSONEncoder().encode(CGVector(dx: 1.5, dy: -2))
    #expect(String(decoding: data, as: UTF8.self) == "[1.5,-2]")
    #expect(try JSONDecoder().decode(CGVector.self, from: data) == CGVector(dx: 1.5, dy: -2))
}
