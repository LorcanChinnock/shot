import Foundation

/// What Shot writes in an image file besides its pixels and scale, so it can read it back later, on any platform.
public struct ImageMetadata: Equatable, Sendable {
    /// A window capture that includes the macOS window shadow, so the editor opened on it later doesn't offer a second.
    public var windowShadow: Bool
    /// What was captured and marked, for agents.
    public var record: CaptureRecord?
    /// The ID of the file's project in `ProjectStore`.
    public var projectID: String?

    public init(windowShadow: Bool = false, record: CaptureRecord? = nil, projectID: String? = nil) {
        self.windowShadow = windowShadow
        self.record = record
        self.projectID = projectID
    }
}

extension ImageMetadata {
    /// What a window capture that includes the macOS window shadow says in its Exif user comment.
    public static let windowShadowComment = "Shot: includes the macOS window shadow"
    /// The XMP namespace `record`, as JSON text, and `projectID` are stored in, as the properties `record` and `project`.
    public static let xmpNamespace = "https://shot.lorcanchinnock.com/ns/capture/1.0/"
}
