import Foundation
import UniformTypeIdentifiers

/// A `shot://` URL, which runs Shot from a launcher, the Shortcuts app or a script, and drives it in `perf.sh` and the
/// ux-qa skill. Every route is parsed here, so a typo in one fails a test rather than a run.
public enum ShotURL: Equatable, Sendable {
    case action(ShotAction)
    /// Pauses or resumes the recording.
    case pause
    case gallery
    /// `section` is the raw name of a Settings section, `nil` for none.
    case settings(section: String?)
    case edit(EditorRoute)

    public enum ParseError: LocalizedError, Equatable {
        /// Not a `shot://` URL at all, which is ignored.
        case notShot
        case missingPath(host: String)
        case unknownHost(String)

        public var errorDescription: String? {
            switch self {
            case .notShot: "Not a shot:// URL"
            case let .missingPath(host): "Missing path for \(host)"
            case let .unknownHost(host): "Unknown action: \(host)"
            }
        }
    }

    public init(_ url: URL) throws(ParseError) {
        guard url.scheme == "shot", let host = url.host() else {
            throw .notShot
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            query.first { $0.name == name }?.value
        }
        switch host {
        case "pause":
            self = .pause
        case "gallery":
            self = .gallery
        case "settings":
            self = .settings(section: value("section"))
        case _ where EditorRoute.hosts.contains(host):
            guard let route = EditorRoute(host: host, path: value("path")) else {
                throw .missingPath(host: host)
            }
            self = .edit(route)
        default:
            guard let action = ShotAction(rawValue: host) else {
                throw .unknownHost(host)
            }
            // `shot://record?full=1` predates `shot://record-fullscreen`; keep it working.
            self = .action(action == .record && value("full") == "1" ? .recordFullscreen : action)
        }
    }
}

/// Which editor a file opens in: `shot://annotate` picks by file type, `shot://edit-video` always uses the video editor.
public enum EditorRoute: Equatable, Sendable {
    case image(URL)
    case video(URL)

    public static let hosts: Set<String> = ["annotate", "edit-video"]

    public init?(host: String, path: String?) {
        guard Self.hosts.contains(host), let path, !path.isEmpty else {
            return nil
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        self = host == "edit-video" ? .video(url) : EditorRoute(fileURL: url)
    }

    public init(fileURL: URL) {
        let isVideo = UTType(filenameExtension: fileURL.pathExtension)?.conforms(to: .movie) == true
        self = isVideo ? .video(fileURL) : .image(fileURL)
    }
}
