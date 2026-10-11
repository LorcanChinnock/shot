import Foundation
import Testing
@testable import ShotModel

@Test func sweepingTemporaryCapturesDeletesOnlyOldFilesAtTheTop() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let old = Date().addingTimeInterval(-2 * TemporaryCaptures.maxAge)
    let stale = folder.appendingPathComponent("old.png")
    let fresh = folder.appendingPathComponent("new.png")
    let segments = folder.appendingPathComponent("segments")
    let segment = segments.appendingPathComponent("part.mp4")
    try FileManager.default.createDirectory(at: segments, withIntermediateDirectories: true)
    for file in [stale, fresh, segment] {
        try Data([1, 2, 3]).write(to: file)
    }
    for item in [stale, segments, segment] {
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: item.path)
    }

    #expect(TemporaryCaptures.sweep(folder) == 1)
    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(FileManager.default.fileExists(atPath: fresh.path))
    #expect(FileManager.default.fileExists(atPath: segment.path))
}

@Test func sweepingAMissingTemporaryFolderDoesNothing() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    #expect(TemporaryCaptures.sweep(missing) == 0)
}
