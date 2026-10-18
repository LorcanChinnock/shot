import Foundation
import Testing
@testable import ShotModel

@Test func aCanvasPathKeepsItsStepsInOrder() {
    var path = CanvasPath()
    #expect(path.isEmpty)
    path.move(to: CGPoint(x: 1, y: 2))
    path.addLine(to: CGPoint(x: 3, y: 4))
    path.addQuadCurve(to: CGPoint(x: 5, y: 6), control: CGPoint(x: 7, y: 8))
    path.addCurve(to: CGPoint(x: 9, y: 10), control1: CGPoint(x: 11, y: 12), control2: CGPoint(x: 13, y: 14))
    path.addArc(tangent1End: CGPoint(x: 15, y: 16), tangent2End: CGPoint(x: 17, y: 18), radius: 2)
    path.addRect(CGRect(x: 0, y: 0, width: 5, height: 5))
    path.closeSubpath()
    #expect(path.elements == [
        .move(to: CGPoint(x: 1, y: 2)),
        .line(to: CGPoint(x: 3, y: 4)),
        .quadCurve(to: CGPoint(x: 5, y: 6), control: CGPoint(x: 7, y: 8)),
        .curve(to: CGPoint(x: 9, y: 10), control1: CGPoint(x: 11, y: 12), control2: CGPoint(x: 13, y: 14)),
        .arc(tangent1End: CGPoint(x: 15, y: 16), tangent2End: CGPoint(x: 17, y: 18), radius: 2),
        .rect(CGRect(x: 0, y: 0, width: 5, height: 5)),
        .close,
    ])
}

@Test func linesBetweenPointsStartASubpathAtTheFirst() {
    var path = CanvasPath()
    path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3)])
    #expect(path.elements == [.move(to: CGPoint(x: 0, y: 0)), .line(to: CGPoint(x: 4, y: 0)), .line(to: CGPoint(x: 4, y: 3))])
    path.addLines(between: [])
    #expect(path.elements.count == 3)
}

@Test func rectsEllipsesAndRoundedRectsStayWhole() {
    let rect = CGRect(x: 2, y: 3, width: 40, height: 30)
    #expect(CanvasPath(rect: rect).elements == [.rect(rect)])
    #expect(CanvasPath(ellipseIn: rect).elements == [.ellipse(in: rect)])
    #expect(CanvasPath(roundedRect: rect, cornerRadius: 6).elements == [.roundedRect(rect, cornerWidth: 6, cornerHeight: 6)])
}
