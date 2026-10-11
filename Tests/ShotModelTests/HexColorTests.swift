import Foundation
import Testing
@testable import ShotModel

@Test func anOpaqueColourIsSixCapitalDigits() {
    #expect(HexColor.string(red: 30 / 255, green: 144 / 255, blue: 1) == "#1E90FF")
    #expect(HexColor.string(red: 0, green: 0, blue: 0) == "#000000")
}

@Test func aTranslucentColourAddsItsAlpha() {
    #expect(HexColor.string(red: 1, green: 0, blue: 0, alpha: 0.5) == "#FF000080")
    #expect(HexColor.string(red: 1, green: 0, blue: 0, alpha: 0) == "#FF000000")
}

@Test func outOfRangeComponentsAreClamped() {
    // Extended-range sRGB, as a P3 display's colours convert to, goes past 0...1.
    #expect(HexColor.string(red: 1.2, green: -0.1, blue: 0.5, alpha: 1.5) == "#FF0080")
}

@Test(arguments: ["#1E90FF", "1e90ff", " #1E90FF ", "#1E90FFFF"])
func hexParsesWithOrWithoutHashInEitherCase(_ hex: String) throws {
    let c = try #require(HexColor.components(hex))
    #expect(c.red == 30.0 / 255)
    #expect(c.green == 144.0 / 255)
    #expect(c.blue == 1)
    #expect(c.alpha == 1)
}

@Test func shortHexDoublesEachDigit() throws {
    let c = try #require(HexColor.components("#F0A"))
    #expect(c.red == 1)
    #expect(c.green == 0)
    #expect(c.blue == 170.0 / 255)
}

@Test func hexReadsAlpha() throws {
    #expect(try #require(HexColor.components("#FF000080")).alpha == 128.0 / 255)
}

@Test(arguments: ["", "#", "#12", "#12345", "#1234567", "#GGGGGG", "#12 456", "red", "##123456", "#１２３４５６"])
func malformedHexIsRejected(_ hex: String) {
    #expect(HexColor.components(hex) == nil)
}

@Test func hexRoundTripsEveryByte() throws {
    for byte in 0...255 {
        let value = CGFloat(byte) / 255
        let hex = HexColor.string(red: value, green: value, blue: value, alpha: value)
        let c = try #require(HexColor.components(hex))
        #expect(HexColor.string(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha) == hex)
    }
}
