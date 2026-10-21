import Foundation

public enum VideoConcatenator {
    public enum ConcatError: LocalizedError {
        case noSegments
        case exportFailed

        public var errorDescription: String? {
            switch self {
            case .noSegments: String(localized: "Nothing was recorded")
            case .exportFailed: String(localized: "Couldn't join the recording's segments")
            }
        }
    }

    /// A segment's system audio and microphone, recorded to their own files so muting can silence only the microphone.
    public struct SegmentAudio: Sendable {
        public let system: URL
        public let microphone: URL

        public init(system: URL, microphone: URL) {
            self.system = system
            self.microphone = microphone
        }

        public var files: [URL] { [system, microphone] }
    }

    /// Joins recording segments end to end through `assembler` without re-encoding the video; one segment with nothing
    /// muted is moved as is. `muted` holds stretches of the joined recording, in seconds, that become silent.
    /// With `audio`, one per segment, the segments' own audio is replaced by a mix of those files, and only the microphone is muted.
    public static func concatenate(_ segments: [URL], audio: [SegmentAudio] = [], to output: URL, muting muted: CutList = CutList(), assembler: any VideoAssembler) async throws {
        guard let first = segments.first else {
            throw ConcatError.noSegments
        }
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        if segments.count == 1, muted.isEmpty, audio.isEmpty {
            try FileManager.default.moveItem(at: first, to: output)
            return
        }
        try await assembler.concatenate(segments, audio: audio, to: output, muting: muted)
        for url in segments + audio.flatMap(\.files) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
