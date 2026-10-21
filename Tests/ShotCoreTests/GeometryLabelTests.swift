import CoreGraphics
import Testing
@testable import ShotCore

@Test func portraitLabelSwapsSides() {
    #expect(AspectRatio.sixteenNine.label(portrait: true) == "9:16")
    #expect(AspectRatio.sixteenNine.label(portrait: false) == "16:9")
    #expect(AspectRatio.free.label(portrait: true) == "Free")
}

@Test func windowParsingFiltersLayerOwnerAndSize() {
    func entry(_ id: Int, layer: Int, pid: Int, size: CGFloat) -> [String: Any] {
        [
            kCGWindowNumber as String: id, kCGWindowLayer as String: layer, kCGWindowOwnerPID as String: pid,
            kCGWindowBounds as String: CGRect(x: 0, y: 0, width: size, height: size).dictionaryRepresentation,
        ]
    }
    let parsed = WindowInfo.parse([entry(1, layer: 0, pid: 5, size: 100), entry(2, layer: 25, pid: 5, size: 100), entry(3, layer: 0, pid: 99, size: 100), entry(4, layer: 0, pid: 5, size: 20)], excludingPID: 99)
    #expect(parsed.map(\.windowID) == [1])
}

@Test func windowParsingKeepsTheAppAndTitleWhenGiven() throws {
    var entry: [String: Any] = [
        kCGWindowNumber as String: 1, kCGWindowLayer as String: 0, kCGWindowOwnerPID as String: 5,
        kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 100, height: 100).dictionaryRepresentation,
    ]
    // Without Screen Recording access the window list leaves the title out.
    let untitled = try #require(WindowInfo.parse([entry], excludingPID: 99).first)
    #expect(untitled.ownerName == nil && untitled.title == nil)
    entry[kCGWindowOwnerName as String] = "Simulator"
    entry[kCGWindowName as String] = "iPhone 17 Pro"
    let titled = try #require(WindowInfo.parse([entry], excludingPID: 99).first)
    #expect(titled.ownerName == "Simulator")
    #expect(titled.title == "iPhone 17 Pro")
}
