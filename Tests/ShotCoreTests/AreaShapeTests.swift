import CoreGraphics
import Testing
@testable import ShotCore

@Suite struct AreaShapeTests {
    @Test func startsFreeAndLandscape() {
        let shape = AreaShape()
        #expect(shape.ratio == .free)
        #expect(!shape.portrait)
        #expect(shape.widthOverHeight == nil)
        #expect(shape.label == "Free")
    }

    @Test func turningSwapsTheSidesAndLabel() {
        var shape = AreaShape(ratio: .sixteenNine)
        #expect(shape.widthOverHeight == 16.0 / 9)
        #expect(shape.label == "16:9")
        shape.turn()
        #expect(shape.portrait)
        #expect(shape.widthOverHeight == 9.0 / 16)
        #expect(shape.label == "9:16")
        shape.turn()
        #expect(shape.label == "16:9")
    }

    @Test func freeAndSquareDoNotTurn() {
        var free = AreaShape(ratio: .free)
        free.turn()
        #expect(!free.portrait)
        var square = AreaShape(ratio: .square)
        square.turn()
        #expect(!square.portrait)
        #expect(square.widthOverHeight == 1)
    }

    @Test func aTurnedShapeKeepsItsOrientationForTheNextRatio() {
        var shape = AreaShape(ratio: .fourThree, portrait: true)
        shape.ratio = .threeTwo
        #expect(shape.label == "2:3")
        shape.ratio = .square
        #expect(shape.label == "1:1")
        #expect(shape.widthOverHeight == 1)
    }
}
