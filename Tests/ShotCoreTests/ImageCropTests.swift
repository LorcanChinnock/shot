import Foundation
import Testing
@testable import ShotCore

@Test func aCropIsTheShareOfTheWholeImageTrimmedOffEachEdge() {
    let full = CGRect(x: 100, y: 50, width: 200, height: 100)
    let crop = ImageCrop(visible: CGRect(x: 120, y: 60, width: 150, height: 50), within: full)
    #expect(crop == ImageCrop(left: 0.1, top: 0.1, right: 0.15, bottom: 0.4))
    #expect(!crop.isEmpty)
    #expect(ImageCrop(visible: full, within: full).isEmpty)
}

@Test func aCropReachingPastTheWholeImageIsClampedToIt() {
    let full = CGRect(x: 0, y: 0, width: 100, height: 100)
    let crop = ImageCrop(visible: CGRect(x: -20, y: 10, width: 200, height: 50), within: full)
    #expect(crop == ImageCrop(left: 0, top: 0.1, right: 0, bottom: 0.4))
}

@Test func theWholeImageIsFoundAgainFromWhatsLeft() {
    let full = CGRect(x: 100, y: 50, width: 200, height: 100)
    let visible = CGRect(x: 120, y: 60, width: 150, height: 50)
    let crop = ImageCrop(visible: visible, within: full)
    let found = crop.fullRect(forVisible: visible)
    #expect(abs(found.minX - full.minX) < 1e-9 && abs(found.minY - full.minY) < 1e-9)
    #expect(abs(found.width - full.width) < 1e-9 && abs(found.height - full.height) < 1e-9)
}

@Test func resizingACroppedImageScalesTheWholeImageWithIt() {
    let crop = ImageCrop(left: 0.25, top: 0, right: 0.25, bottom: 0.5)
    // Half the width and half the height are left, so the whole image is twice the visible size each way.
    let visible = CGRect(x: 10, y: 20, width: 300, height: 80)
    #expect(crop.fullRect(forVisible: visible) == CGRect(x: -140, y: 20, width: 600, height: 160))
    let doubled = CGRect(x: 10, y: 20, width: 600, height: 160)
    #expect(crop.fullRect(forVisible: doubled) == CGRect(x: -290, y: 20, width: 1200, height: 320))
}

@Test func theSourceRectIsOnWholePixelsAndNeverEmpty() {
    let crop = ImageCrop(left: 0.1, top: 0.25, right: 0.2, bottom: 0.25)
    #expect(crop.sourceRect(width: 1000, height: 400) == CGRect(x: 100, y: 100, width: 700, height: 200))
    let everything = ImageCrop(left: 0.6, top: 0, right: 0.6, bottom: 0)
    #expect(everything.sourceRect(width: 10, height: 10).width == 1)
    #expect(ImageCrop.none.sourceRect(width: 30, height: 20) == CGRect(x: 0, y: 0, width: 30, height: 20))
}

@Test func anImageCropRoundTripsThroughJSON() throws {
    let crop = ImageCrop(left: 0.1, top: 0.2, right: 0.3, bottom: 0.05)
    let decoded = try JSONDecoder().decode(ImageCrop.self, from: JSONEncoder().encode(crop))
    #expect(decoded == crop)
}
