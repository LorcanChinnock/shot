import Foundation

/// Finds the open window an agent names, such as "Simulator" or "calculator", ignoring case and accents, or by its
/// app's bundle ID.
public enum WindowMatch {
    public struct Candidate: Equatable, Sendable {
        public var id: UInt32
        public var app: String
        public var title: String
        /// The app's bundle ID, or empty when it has none.
        public var bundleID: String
        /// The window's size in points, for `shot windows`.
        public var width: Double
        public var height: Double

        public init(id: UInt32, app: String, title: String, bundleID: String = "", width: Double = 0, height: Double = 0) {
            self.id = id
            self.app = app
            self.title = title
            self.bundleID = bundleID
            self.width = width
            self.height = height
        }

        /// How it reads in a list: the app, then the title when there is one.
        public var label: String {
            title.isEmpty ? app : "\(app) — \(title)"
        }
    }

    /// The window `query` names best in `candidates`, which are front to back, or `nil` when none does. From best: the
    /// exact title, the exact app name or bundle ID, a title containing it, an app name containing it, and every word of
    /// it somewhere in the app and title. Windows that match equally go to the frontmost. With `bundleID`, only that
    /// app's windows count, and an empty query takes its frontmost.
    public static func best(_ query: String, bundleID: String? = nil, in candidates: [Candidate]) -> Candidate? {
        let app = fold(bundleID ?? "")
        let candidates = app.isEmpty ? candidates : candidates.filter { fold($0.bundleID) == app }
        let wanted = fold(query)
        guard !wanted.isEmpty else {
            return app.isEmpty ? nil : candidates.first
        }
        let words = wanted.split(separator: " ")
        var found: (candidate: Candidate, rank: Int)?
        for candidate in candidates {
            guard let rank = rank(of: candidate, wanted: wanted, words: words), rank < (found?.rank ?? .max) else {
                continue
            }
            found = (candidate, rank)
        }
        return found?.candidate
    }

    /// Up to `limit` windows as lines, so an agent whose query matched nothing can try again.
    public static func listing(_ candidates: [Candidate], limit: Int = 10) -> String {
        guard !candidates.isEmpty else {
            return "No other app has a window open on screen."
        }
        var lines = candidates.prefix(limit).map { "  \($0.label)" }
        if candidates.count > limit {
            lines.append("  and \(candidates.count - limit) more")
        }
        return "Open windows, front to back:\n" + lines.joined(separator: "\n")
    }

    /// The windows as `shot windows` and `list_windows` give them, front to back. The frontmost is the front window of
    /// the app `frontmostBundleID` names, the one the user is working in.
    public static func json(_ candidates: [Candidate], frontmostBundleID: String?) -> JSONValue {
        let front = frontmostBundleID.flatMap { id in id.isEmpty ? nil : candidates.firstIndex { $0.bundleID == id } }
        return .array(candidates.enumerated().map { index, candidate in
            .object([
                "app": .string(candidate.app),
                "bundleID": .string(candidate.bundleID),
                "title": .string(candidate.title),
                "size": .object(["width": .number(candidate.width), "height": .number(candidate.height)]),
                "frontmost": .bool(index == front),
            ])
        })
    }

    private static func rank(of candidate: Candidate, wanted: String, words: [Substring]) -> Int? {
        let title = fold(candidate.title)
        let app = fold(candidate.app)
        if title == wanted { return 0 }
        if app == wanted || (!candidate.bundleID.isEmpty && fold(candidate.bundleID) == wanted) { return 1 }
        if title.contains(wanted) { return 2 }
        if app.contains(wanted) { return 3 }
        let both = app + " " + title
        return words.allSatisfy { both.contains($0) } ? 4 : nil
    }

    /// Lowercased, without accents, with runs of whitespace as one space.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
