import Testing
@testable import ShotCore

@Test func nothingSavedIsTheSystemDefault() {
    #expect(DeviceChoice(savedID: "", savedName: "", connectedIDs: ["BuiltIn"]) == .systemDefault)
    #expect(DeviceChoice(savedID: "", savedName: "Old Mic", connectedIDs: []) == .systemDefault)
}

@Test func aSavedDeviceThatIsConnectedIsChosen() {
    #expect(DeviceChoice(savedID: "USB-1", savedName: "Blue Yeti", connectedIDs: ["BuiltIn", "USB-1"]) == .connected(id: "USB-1"))
}

@Test func aSavedDeviceThatIsUnpluggedStaysChosenAsMissing() {
    // Not System default: the saved device comes back as soon as it's plugged in again.
    #expect(DeviceChoice(savedID: "USB-1", savedName: "Blue Yeti", connectedIDs: ["BuiltIn"]) == .missing(name: "Blue Yeti"))
    #expect(DeviceChoice(savedID: "USB-1", savedName: "", connectedIDs: []) == .missing(name: ""))
}
