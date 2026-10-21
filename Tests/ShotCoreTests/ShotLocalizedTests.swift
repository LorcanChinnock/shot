import Foundation
import Testing
@testable import ShotCore

@Test func aStringWithoutAnEntryReadsAsItsKey() {
    #expect(shotLocalized("Copied") == "Copied")
    #expect(shotLocalized("Step \(3)") == "Step 3")
    #expect(shotLocalized("Exporting… \(40)%") == "Exporting… 40%")
}

@Test func argumentsGoBackInTheirPlaces() {
    let combo = "⇧⌘4"
    let action = "Capture Area"
    #expect(shotLocalized("\(combo) is already used by \(action)") == "⇧⌘4 is already used by Capture Area")
}

