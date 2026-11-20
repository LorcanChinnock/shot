import Foundation

/// What the one Shot window shows while its search field holds a word (#1460). One field searches settings and captures.
public enum MainWindowSearch {
    /// Where the window is: the library, or the settings pages.
    public enum Page: Sendable {
        case library, settings
    }

    /// What fills the window beside the sidebar.
    public enum Content: Equatable, Sendable {
        /// The page as it is with no search.
        case page
        /// The library's grid, filtered in place, as the gallery's search has always worked.
        case filteredLibrary
        /// Matching settings first, with their controls, then the first few matching captures.
        case results
    }

    /// The most captures the results list before "Show all in library".
    public static let captureLimit = 8

    /// What to show for `query` on `page`. On the library, results show only when a setting matches, so searching your
    /// captures works as it always has. "Show all in library" (`showAllCaptures`) goes to the filtered grid. On the
    /// settings pages, any search shows results, which say so when nothing matches.
    public static func content(query: String, page: Page, settingsMatch: Bool, showAllCaptures: Bool) -> Content {
        guard !SettingsSearch.terms(query).isEmpty else {
            return .page
        }
        if showAllCaptures {
            return .filteredLibrary
        }
        switch page {
        case .library: return settingsMatch ? .results : .filteredLibrary
        case .settings: return .results
        }
    }

    /// How many of `matches` captures the results show.
    public static func shownCaptures(of matches: Int) -> Int {
        min(max(matches, 0), captureLimit)
    }

    /// The few words around the first place `query` appears in `text`, both from `TextSearch`, such as "…drop shadow
    /// 2px…", for a capture in the results. `nil` when the text doesn't contain it.
    public static func snippet(of query: String, in text: String, around radius: Int = 24) -> String? {
        guard let wanted = TextSearch.query(query), let match = text.range(of: wanted) else {
            return nil
        }
        let lower = text.index(match.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(match.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        // Whole words only, so the snippet never starts or ends halfway through one.
        var start = lower
        if start != text.startIndex, let space = text[start..<match.lowerBound].firstIndex(where: \.isWhitespace) {
            start = text.index(after: space)
        }
        var end = upper
        if end != text.endIndex, let space = text[match.upperBound..<end].lastIndex(where: \.isWhitespace) {
            end = space
        }
        let words = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (start == text.startIndex ? "" : "…") + words + (end == text.endIndex ? "" : "…")
    }
}
