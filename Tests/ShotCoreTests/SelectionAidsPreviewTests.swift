import CoreGraphics
import ShotCore
import Testing

@Suite struct SelectionAidsPreviewTests {
    private let size = CGSize(width: 390, height: 150)

    @Test func restsAtTheBoardsArea() {
        let layout = SelectionAidsPreviewLayout(size: size, pointer: nil)
        #expect(layout.area == CGRect(x: 40, y: 30, width: 170, height: 80))
        #expect(layout.pixelSize == (340, 160))
        #expect(layout.pixel == (420, 220))
    }

    @Test func followsThePointer() {
        let layout = SelectionAidsPreviewLayout(size: size, pointer: CGPoint(x: 140.5, y: 90.125))
        #expect(layout.area == CGRect(x: 40, y: 30, width: 100.5, height: 60.125))
        #expect(layout.pixelSize == (201, 120))
        #expect(layout.pixel == (281, 180))
        #expect(layout.loupeCentre == CGPoint(x: 140.5, y: 90.5))
    }

    @Test func keepsTheSmallestAreaWhenThePointerCrossesTheAnchor() {
        let layout = SelectionAidsPreviewLayout(size: size, pointer: CGPoint(x: 5, y: 5))
        #expect(layout.area.size == CGSize(width: 24, height: 24))
    }

    @Test func keepsThePointerInside() {
        let layout = SelectionAidsPreviewLayout(size: size, pointer: CGPoint(x: 500, y: 400))
        #expect(layout.pointer == CGPoint(x: 384, y: 144))
    }

    @Test func putsTheLoupeBelowRightWhenItFits() {
        let tall = CGSize(width: 390, height: 300)
        let layout = SelectionAidsPreviewLayout(size: tall, pointer: CGPoint(x: 100, y: 80))
        #expect(layout.loupe == CGRect(x: 112, y: 92, width: 66, height: 66))
    }

    @Test func flipsTheLoupeAboveNearTheBottom() {
        let layout = SelectionAidsPreviewLayout(size: size, pointer: nil)
        #expect(layout.loupe == CGRect(x: 222, y: 32, width: 66, height: 66))
    }

    @Test func flipsTheLoupeLeftNearTheRightEdge() {
        let layout = SelectionAidsPreviewLayout(size: size, pointer: CGPoint(x: 350, y: 60))
        #expect(layout.loupe.maxX == 338)
    }

    @Test func keepsTheLoupeBelowTheTopEdge() {
        let layout = SelectionAidsPreviewLayout(size: CGSize(width: 390, height: 80), pointer: CGPoint(x: 100, y: 60))
        #expect(layout.loupe.minY == SelectionAidsPreviewLayout.margin)
    }
}
