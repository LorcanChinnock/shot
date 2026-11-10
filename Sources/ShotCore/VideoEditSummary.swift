import Foundation

/// What the video editor's title bar says has changed, after "Edited": "Edited · 1 cut · 2 annotations". Each part shows
/// only when it applies, in this order, and an edit none of them describes, such as a moved clip, reads "Edited" alone.
public struct VideoEditSummary: Equatable, Sendable {
    public enum Part: Equatable, Sendable {
        /// The recording's start or end is trimmed off.
        case trimmed
        /// Sections cut out of the middle of the recording.
        case cuts(Int)
        case annotations(Int)
        /// Videos, sounds and pictures added from other files. An added video's own sound isn't counted again.
        case addedClips(Int)
        /// The frame is cropped.
        case cropped
    }

    public let parts: [Part]

    /// `recording` is the file the editor opened, whose clips on the main track are the ones trimmed and cut.
    public init(project: Project, recording: URL) {
        let slack = Project.shortestClip
        let own = project.main.clips.filter { $0.source == recording }
        var parts: [Part] = []
        if let first = own.first, let last = own.last,
           first.sourceStart > slack || last.sourceEnd < last.sourceDuration - slack {
            parts.append(.trimmed)
        }
        // A later clip that starts past where the one before it stopped skips the footage between them; a reordered one
        // doesn't.
        let cuts = zip(own, own.dropFirst()).count { $1.sourceStart > $0.sourceEnd + slack }
        if cuts > 0 {
            parts.append(.cuts(cuts))
        }
        let annotations = project.tracks.reduce(0) { $0 + $1.annotations.count }
        if annotations > 0 {
            parts.append(.annotations(annotations))
        }
        var added = 0
        for track in project.tracks {
            for clip in track.clips where clip.source != recording {
                let isAddedVideosSound = track.kind == .audio && clip.linkedID != nil
                added += isAddedVideosSound ? 0 : 1
            }
        }
        if added > 0 {
            parts.append(.addedClips(added))
        }
        if project.frameCrop != nil {
            parts.append(.cropped)
        }
        self.parts = parts
    }
}
