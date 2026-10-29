import Foundation
import UniformTypeIdentifiers

/// A `shot://` URL, which runs Shot from a launcher, the Shortcuts app or a script, and drives it in
/// `perf.sh`. Every route is parsed here, so a typo in one fails a test rather than a run.
public enum ShotURL: Equatable, Sendable {
    /// `target` is the part of the screen to take, or `nil` to open the overlay on area. A `.screen` target takes the
    /// screen under the pointer at once, with no overlay.
    case action(ShotAction, target: CaptureTarget? = nil)
    /// Pauses or resumes the recording.
    case pause
    case gallery
    /// `section` is the raw name of a Settings section, `nil` for none.
    case settings(section: String?)
    /// Opens the welcome window again.
    case welcome
    /// Takes a full-screen screenshot after counting down `seconds`.
    case captureTimer(seconds: Int)
    case edit(EditorRoute)

    /// Releases register `shot`. Dev builds (ShotDev.app) register `shot-dev`, so the two can run side by side without
    /// one answering URLs meant for the other.
    public static let schemes: Set<String> = ["shot", "shot-dev"]

    /// The routes from before Screenshot and Record took a target.
    private static let captureAliases: [String: (ShotAction, CaptureTarget)] = [
        "capture-area": (.screenshot, .area),
        "capture-window": (.screenshot, .window),
        "capture-fullscreen": (.screenshot, .screen),
        "record-window": (.record, .window),
        "record-fullscreen": (.record, .screen),
    ]

    public enum ParseError: LocalizedError, Equatable {
        /// Not a `shot://` URL at all, which is ignored.
        case notShot
        case missingPath(host: String)
        case unknownHost(String)
        case invalidSeconds(String)

        public var errorDescription: String? {
            switch self {
            case .notShot: "Not a shot:// URL"
            case let .missingPath(host): "Missing path for \(host)"
            case let .unknownHost(host): "Unknown action: \(host)"
            case let .invalidSeconds(value): "Seconds must be a whole number from \(ScreenshotTimer.urlDelays.lowerBound) to \(ScreenshotTimer.urlDelays.upperBound), not \(value)"
            }
        }
    }

    public init(_ url: URL) throws(ParseError) {
        guard let scheme = url.scheme, Self.schemes.contains(scheme), let host = url.host() else {
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
        case "welcome":
            self = .welcome
        case "capture-timer":
            guard let text = value("seconds") else {
                self = .captureTimer(seconds: ScreenshotTimer.defaultDelay)
                break
            }
            guard let seconds = Int(text), ScreenshotTimer.urlDelays.contains(seconds) else {
                throw .invalidSeconds(text)
            }
            self = .captureTimer(seconds: seconds)
        case _ where EditorRoute.hosts.contains(host):
            guard let route = EditorRoute(host: host, path: value("path")) else {
                throw .missingPath(host: host)
            }
            self = .edit(route)
        default:
            if let (action, target) = Self.captureAliases[host] {
                self = .action(action, target: target)
            } else if let action = ShotAction(rawValue: host) {
                // `shot://record?full=1` predates `shot://record-fullscreen`; keep it working.
                self = .action(action, target: action == .record && value("full") == "1" ? .screen : nil)
            } else {
                throw .unknownHost(host)
            }
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
