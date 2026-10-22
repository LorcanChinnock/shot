import CoreGraphics
import Foundation
import NaturalLanguage
@preconcurrency import Translation

/// **Translate Text**: the text Shot reads in a capture, translated on the Mac by Apple's Translation framework, so
/// nothing leaves it. Lines are grouped into paragraphs first, since a sentence broken across lines translates badly
/// line by line, and each paragraph comes back on a line of its own.
public enum TextTranslation {
    /// The capture's lines as paragraphs, in reading order: a line joins the one above when it starts within a line's
    /// height of the same left edge and the gap between them is under half a line, as wrapped text is. Side-by-side
    /// labels and lines further apart stay separate.
    public static func paragraphs(_ text: CaptureText) -> [String] {
        var paragraphs: [(text: String, last: CGRect)] = []
        for line in text.lines {
            let words = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else {
                continue
            }
            if let previous = paragraphs.last?.last, continues(previous, with: line.box) {
                let joined = paragraphs[paragraphs.count - 1].text
                // A word broken with a hyphen at the end of a line joins without a space.
                let glue = joined.hasSuffix("-") && joined.dropLast().last?.isLetter == true ? "" : " "
                paragraphs[paragraphs.count - 1] = ((glue.isEmpty ? String(joined.dropLast()) : joined) + glue + words, line.box)
            } else {
                paragraphs.append((words, line.box))
            }
        }
        return paragraphs.map(\.text)
    }

    /// Whether a line at `next` carries on the paragraph whose last line is at `previous`.
    static func continues(_ previous: CGRect, with next: CGRect) -> Bool {
        let height = max(previous.height, next.height)
        let gap = next.minY - previous.maxY
        return gap >= -height / 4 && gap < height / 2 && abs(next.minX - previous.minX) < height
            && abs(next.height - previous.height) < height / 3
    }

    /// The translation as it's copied: one paragraph a line.
    public static func output(_ translated: [String]) -> String {
        translated.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The language most of `paragraphs` is in, or `nil` when there's too little text to tell.
    public static func language(of paragraphs: [String]) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(paragraphs.joined(separator: "\n"))
        guard let language = recognizer.dominantLanguage, language != .undetermined else {
            return nil
        }
        return Locale.Language(identifier: language.rawValue)
    }

    /// Whether two languages are the same for translating, such as English and British English.
    public static func same(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        a.languageCode == b.languageCode && (a.script == nil || b.script == nil || a.script == b.script)
    }

    public enum Readiness: Equatable, Sendable {
        /// Both languages are on the Mac, so it translates with no prompt.
        case installed
        /// Apple's prompt has to download a language first.
        case needsDownload
        case unsupported
    }

    public static func readiness(from source: Locale.Language, to target: Locale.Language) async -> Readiness {
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: .installed
        case .supported: .needsDownload
        default: .unsupported
        }
    }

    /// The languages Translation can translate into, sorted by their names in `locale`.
    public static func languages(in locale: Locale = .current) async -> [Locale.Language] {
        var seen = Set<String>()
        return await LanguageAvailability().supportedLanguages
            .filter { seen.insert($0.minimalIdentifier).inserted }
            .sorted { name($0, in: locale).localizedStandardCompare(name($1, in: locale)) == .orderedAscending }
    }

    /// A language's name in `locale`, such as "German" or "Chinese (Traditional)".
    public static func name(_ language: Locale.Language, in locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    /// Translates `paragraphs` from `source`, which must be installed with `target`, without any of Apple's UI.
    @available(macOS 26, *)
    public static func translate(_ paragraphs: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        try await translate(paragraphs, with: TranslationSession(installedSource: source, target: target))
    }

    /// Downloads what `session` needs, which shows Apple's prompt, then translates `paragraphs` with it.
    public static func prepareAndTranslate(_ paragraphs: [String], with session: TranslationSession) async throws -> [String] {
        try await session.prepareTranslation()
        return try await translate(paragraphs, with: session)
    }

    /// Translates `paragraphs` with `session`, keeping their order.
    static func translate(_ paragraphs: [String], with session: TranslationSession) async throws -> [String] {
        let requests = paragraphs.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: String($0)) }
        let responses = try await session.translations(from: requests)
        var translated = paragraphs
        for response in responses {
            if let index = response.clientIdentifier.flatMap(Int.init), translated.indices.contains(index) {
                translated[index] = response.targetText
            }
        }
        return translated
    }
}
