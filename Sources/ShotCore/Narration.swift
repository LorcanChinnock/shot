import Foundation

/// What's said in a recording, lined up with the key frames an agent sees, since a model reading frames can't hear the
/// person narrating them. The words come from on-device speech recognition with their times; this groups them into
/// phrases and gives each to the frame on screen when it starts.
public enum Narration {
    /// A recognised word with when it's said, in seconds of the recording. Its text keeps the spaces the recogniser put
    /// around it.
    public struct Word: Equatable, Sendable {
        public var text: String
        public var start: Double
        public var end: Double

        public init(text: String, start: Double, end: Double) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    /// Words said together: up to a sentence's end or a pause.
    public struct Phrase: Equatable, Sendable {
        public var text: String
        public var start: Double
        public var end: Double

        public init(text: String, start: Double, end: Double) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    /// A silence at least this long, in seconds, ends a phrase.
    public static let pause = 0.8
    /// A phrase that runs on without a pause or a full stop is split at this many seconds.
    public static let longestPhrase = 15.0
    /// The most characters of phrases one result carries, so a long talk doesn't crowd out the frames.
    public static let maximumCharacters = 6000

    /// `words` grouped into phrases, in time order. A phrase ends after a word ending a sentence, before a pause of at
    /// least `pause` seconds, or once it has run `longest` seconds. Words with no text or no finite time are left out.
    public static func phrases(_ words: [Word], pause: Double = Self.pause, longest: Double = Self.longestPhrase) -> [Phrase] {
        let spoken = words
            .filter { $0.start.isFinite && $0.end.isFinite && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        var phrases: [Phrase] = []
        var current: [Word] = []
        func close() {
            guard let first = current.first, let last = current.last else {
                return
            }
            phrases.append(Phrase(text: joined(current), start: first.start, end: max(first.start, last.end)))
            current = []
        }
        for word in spoken {
            if let first = current.first, let last = current.last,
               word.start - last.end >= pause || word.start - first.start >= longest {
                close()
            }
            current.append(word)
            if endsSentence(word.text) {
                close()
            }
        }
        close()
        return phrases
    }

    /// `phrases` shared out among frames at `times`, seconds in increasing order: each frame gets the phrases that start
    /// while it's the latest frame shown, from its time up to the next frame's. Phrases before the first frame go with it.
    public static func align(_ phrases: [Phrase], to times: [Double]) -> [[Phrase]] {
        guard !times.isEmpty else {
            return []
        }
        var aligned = Array(repeating: [Phrase](), count: times.count)
        for phrase in phrases {
            // The last frame at or before the phrase's start; a few milliseconds' tolerance for frames decoded a hair late.
            let index = times.lastIndex { $0 <= phrase.start + 0.01 } ?? 0
            aligned[index].append(phrase)
        }
        return aligned
    }

    /// The earliest of `phrases` whose lines fit in `characters`, and how many were left out.
    public static func fitting(_ phrases: [Phrase], characters: Int = Self.maximumCharacters) -> (kept: [Phrase], left: Int) {
        var used = 0
        var kept: [Phrase] = []
        for phrase in phrases {
            used += line(phrase).count
            guard used <= characters else {
                break
            }
            kept.append(phrase)
        }
        return (kept, phrases.count - kept.count)
    }

    /// How a phrase reads in a tool's result: its times in seconds and its words.
    public static func line(_ phrase: Phrase) -> String {
        String(format: "Said at %.1f–%.1fs: ", phrase.start, phrase.end) + "\"\(phrase.text)\""
    }

    /// Recognised words carry their own spaces, on either side, so they're joined as they come (a suffix such as "'s"
    /// has none) and the spacing is evened out.
    static func joined(_ words: [Word]) -> String {
        words.map(\.text).joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return ".?!…".contains(last)
    }

    /// What's said in the recording at `url`, as phrases to line up with its frames, and a line for the agent about
    /// the transcript, if there's anything to say: that nothing was said, that it was cut short, or why there's none.
    static func transcript(of url: URL, hasAudio: Bool) async -> (phrases: [Narration.Phrase], note: String?) {
        guard hasAudio else {
            return ([], nil)
        }
        let words: [Narration.Word]?
        do {
            words = try await SpeechRecognizer.words(in: url)
        } catch {
            return ([], "Couldn't transcribe its sound: \(error.localizedDescription)")
        }
        guard let words else {
            return ([], "Its sound isn't transcribed: that needs macOS 26 and a language with on-device speech recognition.")
        }
        let phrases = Narration.phrases(words)
        guard !phrases.isEmpty else {
            return ([], "Nothing is said in its sound.")
        }
        let fit = Narration.fitting(phrases)
        var note = "\"Said at\" lines are what's said in its sound, transcribed on this Mac, each after the frame on screen as it starts."
        if fit.left > 0, let last = fit.kept.last {
            note += String(format: " The transcript stops at %.1fs to keep this short, leaving out %d more phrases.", last.end, fit.left)
        }
        return (fit.kept, note)
    }
}
