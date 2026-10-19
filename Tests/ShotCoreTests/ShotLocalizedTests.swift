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

#if !canImport(Darwin)
@Test func aKeyResolvesThroughTheGeneratedTable() {
    #expect(localizableEnglish["%@ is already used by %@"]?["other"] == "%1$@ is already used by %2$@")
    #expect(shotLocalized("\(1) items") == "1 item")
    #expect(shotLocalized("\(2) items") == "2 items")
}

@Test func aKeyIsWhatTheAppleTypeMakesOfTheLiteral() {
    let count = 40
    let name = "clip"
    let interpolated: LocalizationValue = "Exporting… \(count)% of \(name)"
    let plain: LocalizationValue = "50% off"
    #expect(interpolated.key == "Exporting… %lld%% of %@")
    #expect(plain.key == "50% off")
}

@Test func positionedArgumentsCanSwapPlaces() {
    let arguments: [LocalizationValue.Argument] = [.string("a"), .integer(2)]
    #expect(LocalizationValue.formatted("%2$lld then %1$@, 100%%", arguments) == "2 then a, 100%")
}
#endif
