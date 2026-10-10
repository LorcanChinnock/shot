import AVFoundation
import Testing
@testable import ShotCore

extension MediaTests {
    @Test func probingAFileReadsItsDurationPictureAndSound() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeScreenRecording(to: url, seconds: 2, audio: true)
        let media = try await MediaProbe.probe(url)
        #expect(abs(media.duration - 2) < 0.1 && media.size == CGSize(width: 640, height: 400) && media.hasAudio)
    }

    @Test func probingARotatedFileReportsItsPlayingSize() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeSolidVideo(to: url, color: .red, size: CGSize(width: 320, height: 180), seconds: 1, rotated: true)
        let media = try await MediaProbe.probe(url)
        #expect(media.size == CGSize(width: 180, height: 320) && !media.hasAudio)
    }

    @Test func probingSomethingThatIsntMediaFails() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: MediaProbe.ProbeError.self) { try await MediaProbe.probe(url) }
    }
}
