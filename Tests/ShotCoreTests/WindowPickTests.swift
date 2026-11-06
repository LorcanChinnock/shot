import CoreGraphics
import Testing
@testable import ShotCore

private let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
private let icon = CGSize(width: 64, height: 64)
private let name = CGSize(width: 140, height: 40)
private let hint = CGSize(width: 260, height: 21)

private func layout(_ target: CGRect, avoiding: [CGRect] = []) -> [(part: WindowPickLabel.Part, frame: CGRect)] {
    WindowPickLabel.layout(icon: icon, name: name, hint: hint, spacing: 10, target: target, in: screen, avoiding: avoiding)
}

@Test func theLabelSitsInTheMiddleOfTheWindowTopToBottom() {
    let parts = layout(CGRect(x: 150, y: 56, width: 980, height: 680))
    #expect(parts.map(\.part) == [.icon, .name, .hint])
    // 64 + 10 + 40 + 10 + 21 = 145 tall, centred on y 396 and rounded to start at 324.
    #expect(parts[0].frame == CGRect(x: 608, y: 405, width: 64, height: 64))
    #expect(parts[1].frame.midX == 640)
    #expect(parts[1].frame.maxY == 395)
    #expect(parts[2].frame.minY == 324)
}

@Test func aSmallWindowDropsTheCameraThenTheHint() {
    #expect(layout(CGRect(x: 100, y: 100, width: 300, height: 120)).map(\.part) == [.name, .hint])
    #expect(layout(CGRect(x: 100, y: 100, width: 200, height: 60)).map(\.part) == [.name])
}

@Test func aWindowPartlyOffScreenCentresTheLabelOnWhatShows() {
    let parts = layout(CGRect(x: -400, y: 100, width: 800, height: 600))
    // On screen: x 0 to 400.
    #expect(parts[1].frame.midX == 200)
}

@Test func aTinyWindowAtTheEdgeKeepsItsLabelOnScreen() {
    let parts = layout(CGRect(x: 1250, y: 780, width: 30, height: 20))
    #expect(parts.map(\.part) == [.name])
    #expect(screen.insetBy(dx: WindowPickLabel.margin, dy: WindowPickLabel.margin).contains(parts[0].frame))
}

@Test func theLabelMovesAboveTheBarWhenItWouldCoverIt() {
    let bar = CGRect(x: 400, y: 330, width: 480, height: 46)
    let parts = layout(CGRect(x: 150, y: 56, width: 980, height: 680), avoiding: [bar])
    let bottom = parts.map(\.frame.minY).min() ?? 0
    #expect(bottom == 388)
    #expect(!parts.contains { $0.frame.intersects(bar) })
}

@Test func theLabelGoesBelowTheBarWhenThereIsNoRoomAbove() {
    let bar = CGRect(x: 400, y: 700, width: 480, height: 46)
    let parts = layout(CGRect(x: 150, y: 600, width: 980, height: 200), avoiding: [bar])
    #expect(!parts.contains { $0.frame.intersects(bar) })
    #expect((parts.map(\.frame.maxY).max() ?? 0) <= 688)
}

@Test func aWindowIsNamedByItsTitleElseItsApp() {
    let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
    #expect(WindowInfo(windowID: 1, frame: frame, ownerPID: 1, ownerName: "MugCo", title: "Mug Co. Support").pickName == "Mug Co. Support")
    #expect(WindowInfo(windowID: 1, frame: frame, ownerPID: 1, ownerName: "MugCo", title: "  ").pickName == "MugCo")
    #expect(WindowInfo(windowID: 1, frame: frame, ownerPID: 1).pickName == nil)
}
