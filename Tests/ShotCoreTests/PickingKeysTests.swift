import Testing
@testable import ShotCore

@Test func pickingKeysListTheOverlaysKeysInOrder() {
    #expect(PickingKey.all.map(\.key) == ["Tab", "B", "D", "S", "R", "M", "C", "I", "⌥", "Esc"])
    #expect(Set(PickingKey.all.map(\.key)).count == PickingKey.all.count)
}

@Test func pickingKeysTakeTheirChoicesFromTheOverlay() {
    let labels = Dictionary(uniqueKeysWithValues: PickingKey.all.map { ($0.key, $0.label) })
    #expect(labels["Tab"] == "Area · Window · Full Screen")
    #expect(labels["B"] == "Leave out browser toolbars")
    #expect(labels["D"] == "Delay 3, 5, 10 s")
    #expect(labels["R"] == "Ratio 1:1, 4:3, 3:2, 16:9")
}

@Test func actionSymbolsAreDistinct() {
    let symbols = ShotAction.allCases.map(\.symbol)
    #expect(Set(symbols).count == symbols.count)
    #expect(ShotAction.screenshot.symbol == "viewfinder")
    #expect(ShotAction.record.symbol == "record.circle")
}
