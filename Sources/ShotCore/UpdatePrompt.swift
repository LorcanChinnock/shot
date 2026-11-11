import Foundation

/// A new version that Sparkle found, as Shot's update window shows it. It mirrors what Sparkle's own window read from the
/// appcast item and the update state, so the window's buttons follow the same rules.
public struct UpdateOffer: Equatable, Sendable {
    /// How far Sparkle got with the update before showing it.
    public enum Stage: Equatable, Sendable {
        /// Nothing is downloaded yet, so Install starts the download.
        case notDownloaded
        /// An earlier session downloaded it, so Install only unpacks and installs it.
        case downloaded
        /// It's unpacked and waiting, so Shot can relaunch into it now or install it when Shot quits.
        case installing
    }

    public var version: String
    public var build: String
    public var installedVersion: String
    public var installedBuild: String
    public var stage: Stage
    /// The feed marks it important, so Sparkle offers no Skip or Later.
    public var isCritical: Bool
    /// A major upgrade, which can be skipped even when it's critical.
    public var isMajorUpgrade: Bool
    /// The feed has no download, only a page to read, so the main button opens that page.
    public var isInformationOnly: Bool
    /// What changed, from the release notes, one line each.
    public var highlights: [String]

    public init(
        version: String, build: String, installedVersion: String, installedBuild: String, stage: Stage = .notDownloaded,
        isCritical: Bool = false, isMajorUpgrade: Bool = false, isInformationOnly: Bool = false, highlights: [String] = []
    ) {
        self.version = version
        self.build = build
        self.installedVersion = installedVersion
        self.installedBuild = installedBuild
        self.stage = stage
        self.isCritical = isCritical
        self.isMajorUpgrade = isMajorUpgrade
        self.isInformationOnly = isInformationOnly
        self.highlights = highlights
    }

    /// The new and installed versions as the window names them. When the two read the same, each gets its build
    /// number, as Sparkle's own window does, so they never look identical.
    public var versions: (new: String, installed: String) {
        guard version == installedVersion else {
            return (version, installedVersion)
        }
        return ("\(version) (\(build))", "\(installedVersion) (\(installedBuild))")
    }
}

/// What the bottom row of the update window shows for an offer. Sparkle's own window decides the same things.
public struct UpdatePromptButtons: Equatable, Sendable {
    /// What the main button does.
    public enum Install: Equatable, Sendable {
        /// Downloads if needed, then installs and relaunches.
        case installAndRelaunch
        /// Opens the release's page, for a feed item with nothing to download.
        case learnMore
    }

    /// What the secondary button says, if it shows.
    public enum Later: Equatable, Sendable {
        case hidden
        /// Puts the offer off until the next check.
        case later
        /// The update is already unpacked, so putting it off installs it when Shot quits.
        case installOnQuit
    }

    public var install: Install
    public var later: Later
    public var showsSkip: Bool
    /// Whether to offer "Install future updates automatically", which Sparkle shows only while it may install updates
    /// by itself, and never for a release with nothing to download.
    public var showsAutomaticInstall: Bool

    /// - Parameters:
    ///   - offer: The version on offer.
    ///   - automaticallyChecks: Whether Check automatically is on. Later means "remind me at the next check", so
    ///     Sparkle hides it when there's no next check.
    ///   - allowsAutomaticUpdates: Sparkle's `allowsAutomaticUpdates`, true while automatic checks are on unless the
    ///     app turns automatic installs off.
    public init(offer: UpdateOffer, automaticallyChecks: Bool, allowsAutomaticUpdates: Bool) {
        install = offer.isInformationOnly ? .learnMore : .installAndRelaunch
        let mustInstall = offer.isCritical && !offer.isMajorUpgrade
        showsSkip = !mustInstall
        if mustInstall || !automaticallyChecks {
            later = .hidden
        } else {
            later = offer.stage == .installing ? .installOnQuit : .later
        }
        showsAutomaticInstall = allowsAutomaticUpdates && !offer.isInformationOnly
    }
}

/// How much of an update has downloaded, for the window's progress bar.
public struct UpdateDownloadProgress: Equatable, Sendable {
    public private(set) var received: UInt64 = 0
    /// The size the server gave, or nil when it gave none.
    public private(set) var expected: UInt64?

    public init() {}

    public mutating func expect(_ length: UInt64) {
        expected = length > 0 ? length : nil
    }

    public mutating func receive(_ length: UInt64) {
        received += length
    }

    /// From 0 to 1, or nil while the size isn't known, when the window shows a spinner instead.
    public var fraction: Double? {
        guard let expected, expected > 0 else {
            return nil
        }
        return min(Double(received) / Double(expected), 1)
    }

    /// The size so far and the total, such as "4.2 MB" and "8.8 MB". The total is never under what's arrived.
    public func sizes(_ format: (UInt64) -> String) -> (received: String, total: String?) {
        (format(received), expected.map { format(max($0, received)) })
    }
}

/// Picks the list of changes out of a release's notes, for the update window's highlights.
public enum ReleaseHighlights {
    public enum Format: Sendable {
        case markdown
        case html
        case plainText
    }

    /// Each bullet in the notes as one plain line, without the links to issues and commits that release-please adds,
    /// and without its bold scope ("**editor:** "). Headings and other text are left out, so notes with no list give
    /// no highlights.
    public static func parse(_ notes: String, format: Format) -> [String] {
        let items: [String]
        switch format {
        case .html:
            items = htmlItems(notes)
        case .markdown, .plainText:
            items = notes.components(separatedBy: .newlines).compactMap(bulletText)
        }
        return items.map(clean).filter { !$0.isEmpty }
    }

    /// The format of notes from a file, from its MIME type or the end of its name, as Sparkle chooses.
    public static func format(mimeType: String?, pathExtension: String?) -> Format {
        let mime = mimeType?.lowercased() ?? ""
        let ext = pathExtension?.lowercased() ?? ""
        if mime == "text/markdown" || ext == "md" || ext == "markdown" {
            return .markdown
        }
        if mime == "text/plain" || ext == "txt" {
            return .plainText
        }
        return .html
    }

    private static func bulletText(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["* ", "- ", "+ ", "• "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count))
        }
        return nil
    }

    private static func htmlItems(_ html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<li[^>]*>(.*?)</li>", options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            Range(match.range(at: 1), in: html).map { decodeEntities(stripTags(String(html[$0]))) }
        }
    }

    private static func clean(_ item: String) -> String {
        var text = item
        // [text](url) becomes text.
        text = replacing(#"\[([^\]]*)\]\([^)]*\)"#, in: text, with: "$1")
        // release-please ends each line with the issue and the commit: (#1149) (31ebfe3).
        text = replacing(#"(\s*\((#\d+|[0-9a-f]{7,40})(,\s*(#\d+|[0-9a-f]{7,40}))*\))+\s*$"#, in: text, with: "")
        // A bold scope at the start: **capture:** replace…
        text = replacing(#"^\*\*[^*]+:\*\*\s*"#, in: text, with: "")
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        text = replacing(#"\s+"#, in: text, with: " ").trimmingCharacters(in: .whitespaces)
        guard let first = text.first else {
            return text
        }
        return first.uppercased() + text.dropFirst()
    }

    private static func stripTags(_ html: String) -> String {
        replacing("<[^>]+>", in: html, with: "")
    }

    private static func decodeEntities(_ text: String) -> String {
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        return entities.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}
