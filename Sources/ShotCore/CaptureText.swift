import Foundation

/// The text in a capture, as ShotCore's `TextRecognizer` reads it: lines in reading order, each with its words. Every
/// box is in the file's pixels with a top-left origin, the same space as the marks in a capture's record.
public struct CaptureText: Equatable, Sendable {
    public struct Word: Equatable, Sendable {
        public var text: String
        public var box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    public struct Line: Equatable, Sendable {
        public var text: String
        public var box: CGRect
        /// How sure the recogniser is of the line, from 0 to 1.
        public var confidence: Double
        /// `text` split at whitespace, in order, as `wordRanges` splits it.
        public var words: [Word]

        public init(text: String, box: CGRect, confidence: Double = 1, words: [Word] = []) {
            self.text = text
            self.box = box
            self.confidence = confidence
            self.words = words
        }

        /// Where each word of `text` is: the runs between whitespace. The recogniser boxes words by these ranges, so
        /// `box(of:)` can find the words a range covers.
        public static func wordRanges(in text: String) -> [Range<String.Index>] {
            var ranges: [Range<String.Index>] = []
            var start: String.Index?
            for index in text.indices {
                if text[index].isWhitespace {
                    if let begun = start {
                        ranges.append(begun ..< index)
                        start = nil
                    }
                } else if start == nil {
                    start = index
                }
            }
            if let start {
                ranges.append(start ..< text.endIndex)
            }
            return ranges
        }

        /// The box around the words `range` of `text` touches, so a match inside a word covers that whole word. The
        /// line's box when its words don't line up with `text`.
        public func box(of range: Range<String.Index>) -> CGRect {
            let ranges = Self.wordRanges(in: text)
            guard ranges.count == words.count else {
                return box
            }
            let touched = zip(ranges, words).filter { $0.0.overlaps(range) }.map(\.1.box)
            guard let first = touched.first else {
                return box
            }
            return touched.dropFirst().reduce(first) { $0.union($1) }
        }

        func json(words: Bool) -> JSONValue {
            var object: [String: JSONValue] = ["text": .string(text), "box": CaptureText.json(box)]
            if words {
                object["confidence"] = .number((confidence * 100).rounded() / 100)
                object["words"] = .array(self.words.map { .object(["text": .string($0.text), "box": CaptureText.json($0.box)]) })
            }
            return .object(object)
        }
    }

    /// The image's size in pixels.
    public var width: Int
    public var height: Int
    public var lines: [Line]

    public init(width: Int, height: Int, lines: [Line]) {
        self.width = width
        self.height = height
        self.lines = lines
    }

    /// Every line, one after another.
    public var string: String {
        lines.map(\.text).joined(separator: "\n")
    }

    /// `lines` top to bottom, and left to right across a row. A line joins a row when its middle is within the height
    /// of the row's first line, so a label and its value side by side read as one row even when their tops differ a
    /// little. Side-by-side columns read across, row by row, as they look rather than column by column.
    public static func readingOrder(_ lines: [Line]) -> [Line] {
        var rows: [[Line]] = []
        for line in lines.sorted(by: { $0.box.minY < $1.box.minY }) {
            if let first = rows.last?.first, line.box.midY <= first.box.maxY {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    /// A line that contains a query, and the box of the words in it that match.
    public struct Hit: Equatable, Sendable {
        public var line: Line
        public var box: CGRect
    }

    /// The lines that contain `query`, ignoring case and accents, in reading order. A blank query matches nothing.
    public func lines(matching query: String) -> [Hit] {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else {
            return []
        }
        return lines.compactMap { line in
            line.text.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]).map { Hit(line: line, box: line.box(of: $0)) }
        }
    }

    /// The image's size, then its text and lines, as `shot text` prints them and `find_text` gives them. `words` adds
    /// each line's words and the recogniser's confidence.
    public func json(words: Bool) -> [String: JSONValue] {
        [
            "size": .object(["width": .number(Double(width)), "height": .number(Double(height))]),
            "text": .string(string),
            "lines": .array(lines.map { $0.json(words: words) }),
        ]
    }

    /// `[x, y, width, height]`, as boxes and rects are everywhere agents see them.
    public static func json(_ box: CGRect) -> JSONValue {
        .array([box.minX, box.minY, box.width, box.height].map { .number(Double($0)) })
    }

    /// Text that looks private, with the box to hide.
    public struct Found: Equatable, Sendable {
        public var kind: SensitiveText.Kind
        public var text: String
        public var box: CGRect
    }

    /// Every email, token and card number of `kinds` in the lines, in reading order. Each box covers the whole words
    /// the match touches, which can be a little more than the match, never less.
    public func sensitive(_ kinds: Set<SensitiveText.Kind> = Set(SensitiveText.Kind.allCases)) -> [Found] {
        lines.flatMap { line in
            SensitiveText.matches(in: line.text, kinds: kinds).map {
                Found(kind: $0.kind, text: String(line.text[$0.range]), box: line.box(of: $0.range))
            }
        }
    }

    /// What `sensitive` finds of `kinds`, one for each box, since two matches in one word share the word's box. The
    /// recogniser's box can stop short of a word's first or last character (a token's last digit has been seen 12 px
    /// outside it), which would leave part of it legible, so each box grows by a quarter of its height at the sides and a
    /// sixth at the top and bottom (at least 2 px), stays on the image and ends on whole pixels. At a side
    /// with another word beside it on the line, it stops 1 px short of that word's box: word boxes can nearly touch, and
    /// hiding part of a neighbour would garble text that isn't private.
    public func toHide(_ kinds: Set<SensitiveText.Kind>) -> [Found] {
        let image = CGRect(x: 0, y: 0, width: width, height: height)
        let words = lines.flatMap(\.words).map(\.box)
        let kept: [Found] = sensitive(kinds).reduce(into: []) { kept, found in
            if !kept.contains(where: { $0.box == found.box }) {
                kept.append(found)
            }
        }
        return kept.map { found in
            let box = found.box
            let side = max(2, (box.height / 4).rounded(.up)), edge = max(2, (box.height / 6).rounded(.up))
            let row = words.filter { $0.minY < box.maxY && $0.maxY > box.minY }
            let left = row.map(\.maxX).filter { $0 <= box.minX }.max().map { min(side, max(0, box.minX - $0 - 1)) } ?? side
            let right = row.map(\.minX).filter { $0 >= box.maxX }.min().map { min(side, max(0, $0 - box.maxX - 1)) } ?? side
            var padded = found
            padded.box = CGRect(x: box.minX - left, y: box.minY - edge, width: box.width + left + right, height: box.height + 2 * edge)
                .integral.intersection(image)
            return padded
        }
    }

    /// Each kind and box `redact` hid, as it reports them: never the text, which would show an agent what was hidden.
    public static func json(hidden: [Found]) -> JSONValue {
        .array(hidden.map { .object(["kind": .string($0.kind.rawValue), "box": json($0.box)]) })
    }
}

/// Finds text that looks private in a line read from a capture: emails, tokens and API keys, and card numbers.
public enum SensitiveText {
    public enum Kind: String, CaseIterable, Sendable {
        case email, token, card

        /// The kinds named in `text`, split by commas, such as `email,token`, ignoring case and spaces; `nil` when one
        /// isn't a kind or none is named.
        public static func list(_ text: String) -> Set<Kind>? {
            let names = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let kinds = names.compactMap(Kind.init(rawValue:))
            return names.isEmpty || kinds.count != names.count ? nil : Set(kinds)
        }
    }

    public struct Match: Equatable, Sendable {
        public var kind: Kind
        public var range: Range<String.Index>
    }

    /// Each match of `kinds` in `text`, in order. Where two overlap, the first found wins: emails, then cards, then
    /// tokens, since an email's name or a card's digits can look like a token too.
    public static func matches(in text: String, kinds: Set<Kind> = Set(Kind.allCases)) -> [Match] {
        var found: [Match] = []
        for kind in order where kinds.contains(kind) {
            let ranges = switch kind {
            case .email: emails(in: text)
            case .card: cards(in: text)
            case .token: tokens(in: text)
            }
            for range in ranges where !found.contains(where: { $0.range.overlaps(range) }) {
                found.append(Match(kind: kind, range: range))
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The order `matches` looks in.
    static let order: [Kind] = [.email, .card, .token]

    static func emails(in text: String) -> [Range<String.Index>] {
        text.matches(of: #/[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}/#).map(\.range)
    }

    /// Runs of 13 to 19 digits, in groups split by single spaces or hyphens, that start with 2 to 6 as every card
    /// network's numbers do and pass the Luhn check. A longer run, such as a card number then its expiry date, is
    /// searched for the longest card in it.
    static func cards(in text: String) -> [Range<String.Index>] {
        var cards: [Range<String.Index>] = []
        for run in text.matches(of: #/\d+(?:[ \-]\d+)*/#) {
            let groups = text[run.range].matches(of: #/\d+/#).map(\.range)
            var start = 0
            while start < groups.count {
                var best: Int?
                var digits = ""
                for end in start ..< groups.count {
                    digits += text[groups[end]]
                    guard digits.count <= 19 else { break }
                    if digits.count >= 13, let first = digits.first, ("2" ... "6").contains(first), luhn(digits) {
                        best = end
                    }
                }
                if let best {
                    cards.append(groups[start].lowerBound ..< groups[best].upperBound)
                    start = best + 1
                } else {
                    start += 1
                }
            }
        }
        return cards
    }

    /// The Luhn checksum card numbers carry: doubling every second digit from the right, the digits' sum ends in 0.
    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (place, character) in digits.reversed().enumerated() {
            guard let digit = character.wholeNumberValue, character.isASCII else { return false }
            let value = place % 2 == 1 ? digit * 2 : digit
            sum += value > 9 ? value - 9 : value
        }
        return !digits.isEmpty && sum % 10 == 0
    }

    /// Keys with a known prefix (OpenAI, Anthropic, Stripe, GitHub, GitLab, Slack, AWS, Google, npm, Hugging Face,
    /// SendGrid), JSON Web Tokens, and any other long run of letters and digits random enough to be a secret.
    static func tokens(in text: String) -> [Range<String.Index>] {
        let prefixed = text.matches(of: #/(?:sk-|sk_live_|sk_test_|rk_live_|pk_live_|ghp_|gho_|ghu_|ghs_|ghr_|github_pat_|glpat-|xox[abprs]-|AKIA|ASIA|AIza|npm_|hf_|SG\.)[A-Za-z0-9_\-.]{16,}/#).map(\.range)
        let jwts = text.matches(of: #/eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}/#).map(\.range)
        let random = text.matches(of: #/[A-Za-z0-9_\-]{24,}/#).map(\.range).filter { looksRandom(text[$0]) }
        // A known prefix or a JWT says where the token starts and ends better than a random run that overlaps it.
        let kept = (prefixed + jwts + random).reduce(into: [Range<String.Index>]()) { kept, range in
            if !kept.contains(where: { $0.overlaps(range) }) {
                kept.append(range)
            }
        }
        return kept.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Whether `word` mixes capitals, small letters and digits with about as much variety as a random key: at least 4
    /// bits a character. Identifiers, words run together and hex hashes such as a commit's don't.
    static func looksRandom(_ word: Substring) -> Bool {
        guard word.contains(where: \.isUppercase), word.contains(where: \.isLowercase), word.contains(where: \.isNumber) else {
            return false
        }
        return entropy(word) >= 4
    }

    /// Shannon entropy in bits a character.
    static func entropy(_ word: Substring) -> Double {
        let counts = Dictionary(word.map { ($0, 1) }, uniquingKeysWith: +)
        let total = Double(word.count)
        return counts.values.reduce(0) { sum, count in
            let p = Double(count) / total
            return sum - p * log2(p)
        }
    }
}
