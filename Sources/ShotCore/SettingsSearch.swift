import Foundation

/// The search at the top of the Settings sidebar, and the arrow keys that move between its sections.
public enum SettingsSearch {
    /// The words typed, folded for matching. No words means no search.
    public static func terms(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether a row matches: every word typed appears somewhere in `fields`, such as the row's name, its description and the
    /// names of the group and section it's in. Case, accents, full-width letters and curly apostrophes don't matter. A word can
    /// match inside another, so "login" finds "Open Shot at login" and 録画 finds 画面録画. An empty search matches every row.
    public static func matches(_ query: String, in fields: [String]) -> Bool {
        let words = terms(query)
        guard !words.isEmpty else {
            return true
        }
        let text = fold(fields.joined(separator: "\n"))
        return words.allSatisfy(text.contains)
    }

    /// The section the arrow keys move to from the one at `index`, `offset` steps away, stopping at the first and last.
    public static func step(from index: Int, by offset: Int, count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        return min(max(index + offset, 0), count - 1)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }
}
