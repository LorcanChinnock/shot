import CoreGraphics
import Foundation

/// **Add Captions**: what you said while recording, as timed captions on the video, from the on-device transcript.
/// Sized and timed to the usual subtitle rules: at most two lines of about 42 characters, on screen for 0.8 to 7 seconds,
/// and never faster than about 20 characters a second.
public enum Captions {
    public struct Caption: Equatable, Sendable {
        /// One or two lines, split with `\n`.
        public var text: String
        /// Seconds of the recording.
        public var start: Double
        public var end: Double

        public init(text: String, start: Double, end: Double) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    static let lineLength = 42
    static let maxLines = 2
    static let shortest = 0.8
    static let longest = 7.0
    static let charactersPerSecond = 20.0
    /// A silence this long, in seconds, starts a new caption, as it ends a phrase.
    static let pause = Narration.pause
    /// The gap kept between one caption and the next, so they don't run together.
    static let gap = 0.04

    /// `words` as captions in time order. A caption ends at a sentence's end, at a pause, or before the words that would
    /// make it too long to fit two lines or stay up under `longest`. Each stays up long enough to read, up to the next.
    public static func captions(_ words: [Narration.Word], duration: Double) -> [Caption] {
        let spoken = words
            .filter { $0.start.isFinite && $0.end.isFinite && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        var groups: [[Narration.Word]] = []
        var current: [Narration.Word] = []
        for word in spoken {
            if let first = current.first, let last = current.last {
                let text = Narration.joined(current + [word])
                if word.start - last.end >= pause || word.end - first.start > longest || lines(text) == nil {
                    groups.append(current)
                    current = []
                }
            }
            current.append(word)
            if Narration.endsSentence(word.text) {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }
        var captions = groups.compactMap { group -> Caption? in
            guard let first = group.first, let last = group.last else { return nil }
            let text = Narration.joined(group)
            return Caption(text: lines(text) ?? text, start: first.start, end: max(first.start, last.end))
        }
        // Long enough to read, without running into the next caption or past the end.
        for index in captions.indices {
            let caption = captions[index]
            let readable = max(shortest, Double(caption.text.count) / charactersPerSecond)
            let limit = min(index + 1 < captions.count ? captions[index + 1].start - gap : duration, caption.start + longest)
            captions[index].end = max(caption.end, min(caption.start + readable, limit))
        }
        return captions
    }

    /// `text` on one line, or split into two at the space that balances them best, when it fits in `maxLines` of
    /// `lineLength`; `nil` when it doesn't.
    static func lines(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count <= lineLength {
            return text
        }
        let spaces = text.indices.filter { text[$0] == " " }
        let splits = spaces.map { (index: $0, first: text.distance(from: text.startIndex, to: $0)) }
            .filter { $0.first <= lineLength && text.count - $0.first - 1 <= lineLength }
        guard maxLines >= 2, let best = splits.min(by: { abs(text.count - 2 * $0.first) < abs(text.count - 2 * $1.first) }) else {
            return nil
        }
        return text[..<best.index] + "\n" + text[text.index(after: best.index)...]
    }

    /// Where each caption shows on the project's timeline, as start and length: the part of it that falls in each kept
    /// piece of `source` on the main track, so trims and cuts take their captions with them.
    public static func placements(_ captions: [Caption], in project: Project, source: URL) -> [(caption: Caption, start: Double, duration: Double)] {
        let pieces = project.tracks.first?.clips.filter { $0.source == source } ?? []
        return captions.compactMap { caption in
            for clip in pieces {
                let from = max(caption.start, clip.sourceStart), to = min(caption.end, clip.sourceEnd)
                if to - from >= TrimRange.minimumLength {
                    return (caption, clip.start + from - clip.sourceStart, to - from)
                }
            }
            return nil
        }
    }

    /// The share of the frame's height a caption's text is, and the least it's drawn at in a GIF at the default width.
    static let textHeight = 0.05
    static let smallestText = 14.0
    /// The share of the frame's height left under the captions.
    static let bottomMargin = 0.075

    /// `caption` as white text in a dark, fully opaque box, centred near the bottom of a `canvas`-sized frame. The box is
    /// opaque so a GIF, which keeps unchanged pixels from frame to frame, only pays for it when the text changes.
    public static func annotation(_ caption: Caption, canvas: CGSize) -> Annotation {
        // A GIF at the default width is scaled to 720 px wide, so keep the text at least `smallestText` there.
        let fontSize = max(canvas.height * textHeight, smallestText * canvas.width / Double(VideoExportOptions().gifWidth)).rounded()
        let size = TextLayout(string: caption.text, fontSize: fontSize, color: RGBA(1, 1, 1)).size
        let padding = fontSize * Annotation.textBoxPadding.vertical
        let origin = CGPoint(x: ((canvas.width - size.width) / 2).rounded(), y: (canvas.height * (1 - bottomMargin) - padding - size.height).rounded())
        var annotation = Annotation(kind: .text(caption.text, origin: origin, fontSize: fontSize), color: RGBA(1, 1, 1), fill: RGBA(0, 0, 0, 1), lineWidth: fontSize / 6)
        annotation.alignment = .center
        return annotation
    }
}
