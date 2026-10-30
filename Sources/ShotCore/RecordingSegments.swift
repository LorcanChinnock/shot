import Foundation

/// The segment files of one recording, in order, and the audio files written beside them.
public struct RecordingSegments: Sendable {
    public private(set) var videos: [URL] = []
    public private(set) var audio: [VideoConcatenator.SegmentAudio] = []

    public init() {}

    /// The audio to join with the videos: all of it, or none when some segment has no audio file of its own.
    public var joinableAudio: [VideoConcatenator.SegmentAudio] {
        audio.count == videos.count ? audio : []
    }

    public mutating func append(_ video: URL, audio segmentAudio: VideoConcatenator.SegmentAudio?) {
        videos.append(video)
        if let segmentAudio {
            audio.append(segmentAudio)
        }
    }

    /// Removes the last segment, with its audio if it has any.
    public mutating func removeLast() -> (video: URL, audio: VideoConcatenator.SegmentAudio?)? {
        guard let video = videos.popLast() else {
            return nil
        }
        return (video, audio.count > videos.count ? audio.popLast() : nil)
    }

    /// Where a new segment and its audio files go. The microphone and system audio get their own files only
    /// when both are on, since SCK mixes the microphone into system audio's track.
    public static func files(in folder: URL, id: String, microphone: Bool, systemAudio: Bool) -> (video: URL, audio: VideoConcatenator.SegmentAudio?) {
        let audio = microphone && systemAudio
            ? VideoConcatenator.SegmentAudio(system: folder.appendingPathComponent("\(id)-system.mov"), microphone: folder.appendingPathComponent("\(id)-microphone.mov"))
            : nil
        return (folder.appendingPathComponent("\(id).mp4"), audio)
    }
}
