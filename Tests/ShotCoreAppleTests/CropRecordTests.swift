import CoreGraphics
import Foundation
import Testing
@testable import ShotCore
import ShotCoreApple

@Test func aCroppedVersionRecordsItsCropAndReopensWithItAdjustable() throws {
    var doc = EditorDocument(base: solidImage(width: 400, height: 300))
    doc.annotations = [Annotation(kind: .counter(1, center: CGPoint(x: 120, y: 100)), color: RGBA.presets[0], lineWidth: 4)]
    let original = URL(fileURLWithPath: "/nowhere/Shot.png")
    let whole = VersionWriter.record(of: doc, drawnOn: original, savedAs: .png, scale: 1)
    #expect(whole.crop == nil)

    doc.crop(to: CGRect(x: 50, y: 40, width: 200, height: 150))
    var record = VersionWriter.record(of: doc, drawnOn: original, savedAs: .png, scale: 1)
    #expect(record.canvas == [50, 40, 200, 150])
    #expect(record.crop == [50, 40, 200, 150])
    #expect(record.editable == true)

    record.size = .init(width: 200, height: 150)
    let layers = try #require(record.editableLayers)
    #expect(layers.crop == CGRect(x: 50, y: 40, width: 200, height: 150))
    let reopened = EditorDocument(base: solidImage(width: 400, height: 300), annotations: layers.annotations, canvasRect: layers.canvas)
    #expect(reopened.frameCrop == layers.crop)
    #expect(reopened.contentRect == reopened.fullRect)
}

@Test func aVersionWithoutACropFieldStillReopensWithoutOne() throws {
    let record = CaptureRecord(original: "Shot.png", kind: "image", created: Date(), size: .init(width: 100, height: 100), scale: 1, canvas: [20, 30, 100, 100], editable: true)
    let layers = try #require(record.editableLayers)
    #expect(layers.crop == nil)
}
