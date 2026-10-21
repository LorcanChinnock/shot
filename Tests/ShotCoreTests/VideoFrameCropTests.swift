import Foundation
import Testing
@testable import ShotCore

@Test func aVideoWithNoFrameCropShowsItsWholeCanvasWithEvenSides() {
    #expect(VideoFrameCrop.outputRect(crop: nil, canvas: CGSize(width: 1920, height: 1080)) == CGRect(x: 0, y: 0, width: 1920, height: 1080))
    #expect(VideoFrameCrop.outputRect(crop: nil, canvas: CGSize(width: 1001, height: 601)).size.width.truncatingRemainder(dividingBy: 2) == 0)
}

@Test func aFrameCropIsTheOutputSizeRoundedDownToEvenSides() {
    let canvas = CGSize(width: 1920, height: 1080)
    #expect(VideoFrameCrop.outputRect(crop: CGRect(x: 160, y: 90, width: 1600, height: 900), canvas: canvas) == CGRect(x: 160, y: 90, width: 1600, height: 900))
    #expect(VideoFrameCrop.outputRect(crop: CGRect(x: 10.4, y: 33.6, width: 1001.7, height: 601), canvas: canvas) == CGRect(x: 10, y: 34, width: 1002, height: 600))
}

@Test func aSquareFrameCropGivesASquareOutput() {
    let canvas = CGSize(width: 1920, height: 1080)
    let square = VideoFrameCrop.outputRect(crop: CGRect(x: 420, y: 0, width: 1080, height: 1080), canvas: canvas)
    #expect(square.width == square.height)
    #expect(square.width == 1080)
}

@Test func aFrameCropIsKeptWithinTheCanvas() {
    let canvas = CGSize(width: 1280, height: 720)
    #expect(VideoFrameCrop.outputRect(crop: CGRect(x: -100, y: 600, width: 500, height: 500), canvas: canvas) == CGRect(x: 0, y: 600, width: 400, height: 120))
}

@Test func aFrameCropShowingEverythingOrTooLittleIsNone() {
    let canvas = CGSize(width: 1280, height: 720)
    #expect(VideoFrameCrop.normalized(CGRect(origin: .zero, size: canvas), canvas: canvas) == nil)
    #expect(VideoFrameCrop.normalized(CGRect(x: -5, y: -5, width: 2000, height: 2000), canvas: canvas) == nil)
    #expect(VideoFrameCrop.normalized(CGRect(x: 10, y: 10, width: 8, height: 400), canvas: canvas) == nil)
    #expect(VideoFrameCrop.normalized(CGRect(x: 0, y: 25, width: 1280, height: 695), canvas: canvas) == CGRect(x: 0, y: 25, width: 1280, height: 694))
}

@Test func aFrameCropShowingAllOfAnOddSizedCanvasIsNone() {
    let canvas = CGSize(width: 1001, height: 701)
    #expect(VideoFrameCrop.normalized(CGRect(origin: .zero, size: canvas), canvas: canvas) == nil)
    #expect(VideoFrameCrop.normalized(CGRect(x: 0, y: 0, width: 1001, height: 600), canvas: canvas) == CGRect(x: 0, y: 0, width: 1000, height: 600))
}

@Test func aClipCropLeavesThePartOfThePictureNotTrimmed() {
    let crop = ImageCrop(left: 0.25, top: 0.1, right: 0.25, bottom: 0.4)
    #expect(crop.keptRect(in: CGSize(width: 400, height: 200)) == CGRect(x: 100, y: 20, width: 200, height: 100))
    #expect(ImageCrop.none.keptRect(in: CGSize(width: 40, height: 30)) == CGRect(x: 0, y: 0, width: 40, height: 30))
}
