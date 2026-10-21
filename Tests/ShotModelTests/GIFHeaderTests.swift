import Foundation
import Testing
@testable import ShotModel

/// A GIF `GIFEncoder` wrote, of `count` frames of `width` × `height`, each a different gray.
private func gif(width: Int, height: Int, count: Int) throws -> Data {
    var data = Data()
    let encoder = GIFEncoder(width: width, height: height) { data += $0 }
    for index in 0 ..< count {
        let gray = UInt32(index * 40)
        var pixels = [UInt32](repeating: (gray | gray << 8 | gray << 16 | 255 << 24).littleEndian, count: width * height)
        try encoder.add(&pixels, delay: 0.1)
    }
    try encoder.finish()
    return data
}

@Test func aGIFsHeaderGivesItsSizeAndFrames() throws {
    let header = try #require(GIFHeader(try gif(width: 80, height: 60, count: 5)))
    #expect(header == GIFHeader(width: 80, height: 60, frames: 5))
}

@Test func aGIFCutShortCountsTheFramesBeforeTheCut() throws {
    let whole = try gif(width: 40, height: 30, count: 3)
    #expect(GIFHeader(whole.dropLast())?.frames == 3)
    // Partway through the third frame's pictures.
    #expect(GIFHeader(whole.prefix(whole.count - 4))?.frames == 2)
}

@Test func onlyAGIFHasAGIFHeader() throws {
    #expect(GIFHeader(Data("GIF89a".utf8)) == nil)
    #expect(GIFHeader(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 0, count: 20))) == nil)
    var noFrames = Data("GIF89a".utf8) + [10, 0, 10, 0, 0, 0, 0]
    noFrames.append(0x3B)
    #expect(GIFHeader(noFrames) == nil)
}
