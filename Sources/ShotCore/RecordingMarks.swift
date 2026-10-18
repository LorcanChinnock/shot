#if canImport(Darwin)
import Foundation

/// The marks agents stamped on their recordings, kept app-private so the capture folder gets no extra file and a shared
/// video says nothing about them: `~/Library/Application Support/<bundle ID>/recording-marks.json`, by the recording's
/// path. The app writes it when an agent's recording is saved; the MCP server reads it for `get_frames`. A recording
/// that's moved or renamed loses its marks.
public enum RecordingMarks {
    /// The store for the app with `bundleID`, so Shot and ShotDev keep their own.
    public static func url(bundleID: String) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("recording-marks.json")
    }

    /// The marks of the recording at `video`, or none when the store has none for it or can't be read.
    public static func marks(for video: URL, in store: URL) -> [RecordingMark] {
        load(store)[video.standardizedFileURL.path] ?? []
    }

    /// Keeps `marks` for the recording at `video`, and forgets the marks of recordings that are gone. Written
    /// atomically, so a reader never sees half of it.
    public static func save(_ marks: [RecordingMark], for video: URL, in store: URL) throws {
        var all = load(store).filter { FileManager.default.fileExists(atPath: $0.key) }
        all[video.standardizedFileURL.path] = marks.isEmpty ? nil : marks
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(all).write(to: store, options: .atomic)
    }

    private static func load(_ store: URL) -> [String: [RecordingMark]] {
        guard let data = try? Data(contentsOf: store) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: [RecordingMark]].self, from: data)) ?? [:]
    }
}
#endif
