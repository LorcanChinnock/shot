import Foundation

/// Finds the open window an agent names, such as "Simulator" or "calculator", ignoring case and accents.
public enum WindowMatch {
    public struct Candidate: Equatable, Sendable {
        public var id: UInt32
        public var app: String
        public var title: String

        public init(id: UInt32, app: String, title: String) {
            self.id = id
            self.app = app
            self.title = title
        }

        /// How it reads in a list: the app, then the title when there is one.
        public var label: String {
            title.isEmpty ? app : "\(app) — \(title)"
        }
    }

    /// The window `query` names best in `candidates`, which are front to back, or `nil` when none does. From best: the
    /// exact title, the exact app name, a title containing it, an app name containing it, and every word of it somewhere
    /// in the app and title. Windows that match equally go to the frontmost.
    public static func best(_ query: String, in candidates: [Candidate]) -> Candidate? {
        let wanted = fold(query)
        guard !wanted.isEmpty else {
            return nil
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

    private static func rank(of candidate: Candidate, wanted: String, words: [Substring]) -> Int? {
        let title = fold(candidate.title)
        let app = fold(candidate.app)
        if title == wanted { return 0 }
        if app == wanted { return 1 }
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
