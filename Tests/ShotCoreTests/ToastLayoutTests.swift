import CoreGraphics
import ShotCore
import Testing

struct ToastLayoutTests {
    private let visible = CGRect(x: 0, y: 40, width: 1440, height: 800)
    private let size = CGSize(width: 260, height: 36)

    @Test func sitsInTheLeftCornerWhereACardWouldWithNoCards() {
        let frame = ToastLayout.frame(size: size, in: visible, side: .left, edgeInset: 30, cardsTop: nil)
        #expect(frame == CGRect(x: 30, y: 70, width: 260, height: 36))
    }

    @Test func linesUpWithTheCardsOnTheRight() {
        let frame = ToastLayout.frame(size: size, in: visible, side: .right, edgeInset: 30, cardsTop: nil)
        #expect(frame.maxX == 1410)
    }

    @Test func restsAboveTheCards() {
        let frame = ToastLayout.frame(size: size, in: visible, side: .left, edgeInset: 30, cardsTop: 260)
        #expect(frame.minY == 282)
    }

    @Test func staysOnScreenAboveATallStack() {
        let frame = ToastLayout.frame(size: size, in: visible, side: .left, edgeInset: 30, cardsTop: 830)
        #expect(frame.maxY == 840)
    }

    @Test func staysOnScreenWhenWiderThanTheCorner() {
        let wide = CGSize(width: 1430, height: 36)
        let frame = ToastLayout.frame(size: wide, in: visible, side: .right, edgeInset: 30, cardsTop: nil)
        #expect(frame.minX == 0)
    }

    @Test func growsAwayFromTheLeftSide() {
        let frame = ToastLayout.resized(CGRect(x: 30, y: 70, width: 260, height: 36), to: CGSize(width: 400, height: 36), side: .left)
        #expect(frame == CGRect(x: 30, y: 70, width: 400, height: 36))
    }

    @Test func growsAwayFromTheRightSide() {
        let frame = ToastLayout.resized(CGRect(x: 1150, y: 70, width: 260, height: 36), to: CGSize(width: 400, height: 36), side: .right)
        #expect(frame == CGRect(x: 1010, y: 70, width: 400, height: 36))
    }
}
