import Foundation
import Testing
@testable import ShotCore

@Test func stampingAMovieKeepsItAndAddsTheID() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let movie = folder.appendingPathComponent("Recording.mp4")
    // An ftyp box, then an mdat of 4 bytes, so the boxes run to the end of the file.
    let boxes = Data([0, 0, 0, 16] + Array("ftypisom".utf8) + [0, 0, 2, 0] + [0, 0, 0, 12] + Array("mdat".utf8) + [1, 2, 3, 4])
    try boxes.write(to: movie)

    try ProjectStamp.stamp(movieAt: movie, id: "ID-1")
    #expect(ProjectStamp.id(ofFileAt: movie) == "ID-1")
    #expect(try Data(contentsOf: movie) == boxes + MovieStampBox.box(id: "ID-1"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Recording.mp4"])
    try ProjectStamp.stamp(movieAt: movie, id: "ID-2")
    #expect(ProjectStamp.id(ofFileAt: movie) == "ID-2")
}

@Test func aFileThatHoldsNoIDKeepsItsProjectByItsIdentity() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let gif = folder.appendingPathComponent("Clip.gif")
    try Data("GIF89a".utf8).write(to: gif)
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let saved = try store.save(String?.none, for: gif, id: nil)
    #expect(ProjectKey.isIdentity(saved.id))
    #expect(store.entry(for: gif)?.id == saved.id)
}
