import Foundation

/// What Shot writes in an image file besides its pixels and scale, so it can read it back later, on any platform.
public struct ImageMetadata: Equatable, Sendable {
    /// A window capture that includes the macOS window shadow, so the editor opened on it later doesn't offer a second.
    public var windowShadow: Bool
    /// The ID of the file's project in `ProjectStore`.
    public var projectID: String?

    public init(windowShadow: Bool = false, projectID: String? = nil) {
        self.windowShadow = windowShadow
        self.projectID = projectID
    }
}

extension ImageMetadata {
    /// What a window capture that includes the macOS window shadow says in its Exif user comment.
    public static let windowShadowComment = "Shot: includes the macOS window shadow"
    /// The XMP namespace `projectID` is stored in, as the property `project`. Older versions of Shot also stored a
    /// capture record there, which is ignored now.
    public static let xmpNamespace = "https://shot.lorcanchinnock.com/ns/capture/1.0/"
}
