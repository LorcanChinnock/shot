import Foundation

/// Decides what to do with the files a recording that never finished leaves in the segments folder: which to try to
/// recover, which to leave alone because another copy of Shot may still be writing them, and which to sweep.
public enum SegmentRecovery {
    /// How long a file must have gone unchanged before it's treated as left over, in case another copy of Shot is recording into the same folder.
    public static let settleTime: TimeInterval = 600

    public struct File: Equatable, Sendable {
        public let name: String
        public let modified: Date

        public init(name: String, modified: Date) {
            self.name = name
            self.modified = modified
        }
    }

    /// One segment's video and, when the microphone and system audio were both on, the two files they were written to apart.
    public struct Segment: Equatable, Sendable {
        public let id: String
        public let video: String
        public let system: String?
        public let microphone: String?
        public let modified: Date

        public var files: [String] { [video] + [system, microphone].compactMap { $0 } }
    }

    public struct Plan: Equatable, Sendable {
        /// Segments whose video is old enough to recover, in the order they were recorded.
        public let segments: [Segment]
        /// Old files that can't be recovered: audio whose video is gone, or files Shot didn't write.
        public let orphans: [String]
    }

    private static let videoSuffix = ".mp4"
    private static let systemSuffix = "-system.mov"
    private static let microphoneSuffix = "-microphone.mov"

    public static func plan(_ files: [File], now: Date = Date()) -> Plan {
        let cutoff = now.addingTimeInterval(-settleTime)
        var videos: [String: File] = [:]
        var system: [String: File] = [:]
        var microphone: [String: File] = [:]
        var orphans: [String] = []
        for file in files where file.modified < cutoff {
            if file.name.hasSuffix(systemSuffix) {
                system[String(file.name.dropLast(systemSuffix.count))] = file
            } else if file.name.hasSuffix(microphoneSuffix) {
                microphone[String(file.name.dropLast(microphoneSuffix.count))] = file
            } else if file.name.hasSuffix(videoSuffix) {
                videos[String(file.name.dropLast(videoSuffix.count))] = file
            } else {
                orphans.append(file.name)
            }
        }
        let segments = videos.map { id, video in
            Segment(id: id, video: video.name, system: system[id]?.name, microphone: microphone[id]?.name, modified: video.modified)
        }
        .sorted { ($0.modified, $0.id) < ($1.modified, $1.id) }
        orphans += system.filter { videos[$0.key] == nil }.values.map(\.name)
        orphans += microphone.filter { videos[$0.key] == nil }.values.map(\.name)
        return Plan(segments: segments, orphans: orphans.sorted())
    }

    /// The segments' own audio files, one pair per segment, or nil unless every segment has both: a join takes all or none of them.
    public static func audio(of segments: [Segment]) -> [(system: String, microphone: String)]? {
        var pairs: [(system: String, microphone: String)] = []
        for segment in segments {
            guard let system = segment.system, let microphone = segment.microphone else {
                return nil
            }
            pairs.append((system, microphone))
        }
        return pairs.isEmpty ? nil : pairs
    }
}
