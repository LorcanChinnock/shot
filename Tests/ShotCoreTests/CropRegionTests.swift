import Foundation
import Testing
@testable import ShotCore

@Test func aRegionIsGrownToWholePixelsAndKeptOnTheImage() {
    #expect(CropRegion.clamped([10, 20, 30, 40], width: 200, height: 120) == [10, 20, 30, 40])
    #expect(CropRegion.clamped([10.5, 20.2, 30, 40], width: 200, height: 120) == [10, 20, 31, 41])
    #expect(CropRegion.clamped([-10, -5, 50, 50], width: 200, height: 120) == [0, 0, 40, 45])
    #expect(CropRegion.clamped([150, 100, 500, 500], width: 200, height: 120) == [150, 100, 50, 20])
    #expect(CropRegion.clamped([0, 0, 1e300, 1e300], width: 200, height: 120) == [0, 0, 200, 120])
    #expect(CropRegion.clamped([0.2, 0.2, 0.1, 0.1], width: 200, height: 120) == [0, 0, 1, 1])
}

@Test func aRegionOffTheImageOrNotARectangleIsNone() {
    #expect(CropRegion.clamped([200, 0, 10, 10], width: 200, height: 120) == nil)
    #expect(CropRegion.clamped([-20, 0, 20, 10], width: 200, height: 120) == nil)
    #expect(CropRegion.clamped([0, 500, 10, 10], width: 200, height: 120) == nil)
    #expect(CropRegion.clamped([0, 0, 0, 10], width: 200, height: 120) == nil)
    #expect(CropRegion.clamped([0, 0, 10], width: 200, height: 120) == nil)
    #expect(CropRegion.clamped([.nan, 0, 10, 10], width: 200, height: 120) == nil)
    #expect(CropRegion.clamped([0, 0, 10, 10], width: 0, height: 0) == nil)
}

@Test func aToolsRectIsFourFiniteNumbersWithASize() {
    let numbers = { (values: [Double]) in JSONValue.array(values.map(JSONValue.number)) }
    #expect(CropRegion.rect(numbers([1, 2, 3, 4])) == [1, 2, 3, 4])
    #expect(CropRegion.rect(numbers([1, 2, 3])) == nil)
    #expect(CropRegion.rect(numbers([1, 2, 0, 4])) == nil)
    #expect(CropRegion.rect(.array([.number(1), .number(2), .string("three"), .number(4)])) == nil)
    #expect(CropRegion.rect(.array([.number(1), .number(2), .string("3"), .number(4)])) == [1, 2, 3, 4])
    #expect(CropRegion.rect(.string("1,2,3,4")) == nil)
    #expect(CropRegion.rect(nil) == nil)
    #expect(CropRegion.text([1.5, 2, 3.333, 4]) == "1.5,2,3.33,4")
}
