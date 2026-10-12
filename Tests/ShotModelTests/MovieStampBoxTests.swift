import Foundation
import Testing
@testable import ShotModel

@Test func aStampBoxHoldsTheIDAfterShotsExtendedType() throws {
    let data = MovieStampBox.box(id: "ID-1")
    let box = try #require(MovieStampBox.box(header: data, at: 0, fileSize: UInt64(data.count)))
    #expect(box == MovieStampBox.Box(offset: 0, size: UInt64(data.count), headerSize: 8, type: "uuid"))
    #expect(MovieStampBox.id(inUUIDBody: data.dropFirst(8)) == "ID-1")
}

@Test func anotherAppsUUIDBoxHoldsNoID() {
    #expect(MovieStampBox.id(inUUIDBody: Data(repeating: 7, count: 16) + Data("ID-1".utf8)) == nil)
    #expect(MovieStampBox.id(inUUIDBody: Data(MovieStampBox.userType)) == nil)
}

@Test func aBoxWithALargeSizeReadsIt() {
    let header = Data([0, 0, 0, 1] + Array("mdat".utf8) + [0, 0, 0, 1, 0, 0, 0, 0])
    #expect(MovieStampBox.box(header: header, at: 8, fileSize: 8 + (1 << 32)) == MovieStampBox.Box(offset: 8, size: 1 << 32, headerSize: 16, type: "mdat"))
}

@Test func aBoxThatRunsPastTheFileOrToItsEndIsntWhole() {
    let header = Data([0, 0, 0, 100] + Array("moov".utf8))
    #expect(MovieStampBox.box(header: header, at: 0, fileSize: 99) == nil)
    #expect(MovieStampBox.box(header: header, at: 10, fileSize: 100) == nil)
    #expect(MovieStampBox.box(header: Data([0, 0, 0, 0] + Array("mdat".utf8)), at: 0, fileSize: 100) == nil)
    #expect(MovieStampBox.box(header: Data([0, 0, 0, 4] + Array("free".utf8)), at: 0, fileSize: 100) == nil)
    #expect(MovieStampBox.box(header: Data([0, 0, 0]), at: 0, fileSize: 100) == nil)
}

@Test func boxesTileAMovieOnlyWhenTheyRunEndToEndToItsSize() {
    let ftyp = MovieStampBox.Box(offset: 0, size: 20, headerSize: 8, type: "ftyp")
    let moov = MovieStampBox.Box(offset: 20, size: 80, headerSize: 8, type: "moov")
    #expect(MovieStampBox.tiles([ftyp, moov], fileSize: 100))
    #expect(!MovieStampBox.tiles([ftyp, moov], fileSize: 120))
    #expect(!MovieStampBox.tiles([ftyp], fileSize: 100))
    #expect(!MovieStampBox.tiles([], fileSize: 0))
}
