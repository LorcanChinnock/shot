import CoreGraphics
import Testing
@testable import ShotCore

struct PermissionCardPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let card = CGSize(width: 300, height: 180)

    @Test func sitsAboveABarAtTheBottom() {
        let bar = CGRect(x: 520, y: 40, width: 400, height: 34)
        let origin = PermissionCardPlacement.origin(for: card, bar: bar, screen: screen)
        #expect(origin == CGPoint(x: 570, y: 90))
    }

    @Test func sitsBelowABarAtTheTop() {
        let bar = CGRect(x: 520, y: 820, width: 400, height: 34)
        let origin = PermissionCardPlacement.origin(for: card, bar: bar, screen: screen)
        #expect(origin == CGPoint(x: 570, y: 624))
    }

    @Test func centresOnTheScreenWithoutABar() {
        let origin = PermissionCardPlacement.origin(for: card, bar: nil, screen: screen)
        #expect(origin == CGPoint(x: 570, y: 360))
    }

    @Test func staysOnTheScreen() {
        // A bar on a second display to the left, pushed to its edge: the card keeps 8 pt inside.
        let left = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let bar = CGRect(x: -1290, y: 40, width: 200, height: 34)
        let origin = PermissionCardPlacement.origin(for: card, bar: bar, screen: left)
        #expect(origin.x == -1272)
        #expect(origin.y == 90)
    }

    @Test func roundsToWholePoints() {
        let bar = CGRect(x: 520.5, y: 40.25, width: 401, height: 34)
        let origin = PermissionCardPlacement.origin(for: card, bar: bar, screen: screen)
        #expect(origin.x == origin.x.rounded())
        #expect(origin.y == origin.y.rounded())
    }
}
