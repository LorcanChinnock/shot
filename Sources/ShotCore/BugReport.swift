import Foundation

/// **Copy Bug Report**: what a model is told about a capture or recording, and how its reply becomes Markdown repro
/// steps. Gathering the frames, text and transcript, and asking the model, happen elsewhere; this is the part that
/// needs no window or model, so it's tested.
public enum BugReport {
    /// One still the model sees, with what's on screen in it and what's said around it.
    public struct Frame: Equatable, Sendable {
        /// Seconds from the start of a recording; `nil` for a screenshot.
        public var time: Double?
        /// The lines of text read from the frame, in reading order.
        public var text: [String]
        /// What's said from this frame until the next.
        public var said: [Narration.Phrase]

        public init(time: Double? = nil, text: [String] = [], said: [Narration.Phrase] = []) {
            self.time = time
            self.text = text
            self.said = said
        }
    }

    /// Everything known about the capture.
    public struct Input: Equatable, Sendable {
        public var app: String?
        public var windowTitle: String?
        /// The length of a recording in seconds; `nil` for a screenshot.
        public var duration: Double?
        /// The user's own notes on the capture.
        public var notes: [String]
        public var frames: [Frame]

        public init(app: String? = nil, windowTitle: String? = nil, duration: Double? = nil, notes: [String] = [], frames: [Frame]) {
            self.app = app
            self.windowTitle = windowTitle
            self.duration = duration
            self.notes = notes
            self.frames = frames
        }
    }

    /// How much of the input one model takes. Apple's on-device model has a context of 8,192 tokens, images included,
    /// so it gets few frames and little text; a provider's model takes more.
    public struct Budget: Equatable, Sendable {
        public var frames: Int
        public var transcriptCharacters: Int
        public var textCharacters: Int

        public init(frames: Int, transcriptCharacters: Int, textCharacters: Int) {
            self.frames = frames
            self.transcriptCharacters = transcriptCharacters
            self.textCharacters = textCharacters
        }

        public static let onDevice = Budget(frames: 3, transcriptCharacters: 1500, textCharacters: 1200)
        public static let provider = Budget(frames: 8, transcriptCharacters: 6000, textCharacters: 4000)
    }

    /// What goes to the model: the frames kept, and the request for them.
    public struct Prepared: Equatable, Sendable {
        /// Indexes into the input's frames, in order. The caller sends these frames' images.
        public var frames: [Int]
        public var request: ImageRequest
        /// Every line of text read from the input, which the reply's error text is checked against.
        public var text: [String]
        /// How much was left out to fit, for the report to say so.
        public var trimmed: Bool
    }

    /// `input` cut down to `budget`. Frames are spread evenly, always keeping the first and the last. The text of a
    /// dropped frame is dropped with it, and a line that repeats from the frame before is said once.
    public static func prepare(_ input: Input, budget: Budget) -> Prepared {
        let kept = evenlySpread(input.frames.count, keeping: budget.frames)
        var trimmed = kept.count < input.frames.count
        var seen = Set<String>()
        var allText: [String] = []
        var lines: [String] = []
        var textUsed = 0
        for (position, index) in kept.enumerated() {
            let frame = input.frames[index]
            var label = "Image \(position + 1)"
            if let time = frame.time {
                label += String(format: " (at %.1fs)", time)
            }
            var text: [String] = []
            for line in frame.text {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty, seen.insert(trimmedLine).inserted else { continue }
                allText.append(trimmedLine)
                if textUsed + trimmedLine.count + 1 <= budget.textCharacters {
                    textUsed += trimmedLine.count + 1
                    text.append(trimmedLine)
                } else {
                    trimmed = true
                }
            }
            lines.append(label + (text.isEmpty ? " shows no readable text." : " shows the text:"))
            lines += text.map { "  " + $0 }
        }
        // Words said between the frames kept still belong to the recording, so the whole transcript is offered.
        let allSaid = input.frames.flatMap(\.said)
        let transcript = Narration.fitting(allSaid, characters: budget.transcriptCharacters)
        if transcript.left > 0 { trimmed = true }

        var prompt: [String] = []
        if input.duration != nil {
            prompt.append("The images are frames from a screen recording\(input.duration.map { String(format: " that runs %.1fs", $0) } ?? ""), in order.")
        } else {
            prompt.append("The image is a screenshot.")
        }
        if let app = input.app {
            prompt.append("Captured from \(app)" + (input.windowTitle.map { ", window \"\($0)\"." } ?? "."))
        }
        if !input.notes.isEmpty {
            prompt.append("The user's notes: " + input.notes.map { "\"\($0)\"" }.joined(separator: ", ") + ".")
        }
        prompt.append("Text read from the images by the Mac:")
        prompt += lines
        if !transcript.kept.isEmpty {
            prompt.append("What the user said while recording:")
            prompt += transcript.kept.map(Narration.line)
        }
        prompt.append("Write the bug report.")
        let request = ImageRequest(instructions: instructions, prompt: prompt.joined(separator: "\n"), maxLongEdge: 1536)
        return Prepared(frames: kept, request: request, text: allText, trimmed: trimmed)
    }

    static let instructions = """
    You turn a screenshot or screen recording into a bug report that someone else can reproduce. Use only what the \
    images, the text read from them and the user's words show. Don't guess at causes or versions. Steps are short \
    imperative sentences, one action each. If the images don't show what was expected, say "Not shown". \
    List any error message exactly as it appears in the text read from the images; leave the list empty when there is none.
    """

    /// `n` indexes of `count` items, evenly spread and always including the first and the last.
    static func evenlySpread(_ count: Int, keeping n: Int) -> [Int] {
        guard count > 0, n > 0 else { return [] }
        guard count > n else { return Array(0 ..< count) }
        guard n > 1 else { return [0] }
        return (0 ..< n).map { Int((Double($0) * Double(count - 1) / Double(n - 1)).rounded()) }
    }

    /// What the model replies with: one flat object, which every provider's structured output accepts.
    public static let schema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "title": .object(["type": .string("string")]),
            "steps": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
            "expected": .object(["type": .string("string")]),
            "actual": .object(["type": .string("string")]),
            "errors": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
        ]),
        "required": .array(["title", "steps", "expected", "actual", "errors"].map(JSONValue.string)),
        "additionalProperties": .bool(false),
    ])

    /// The reply as Markdown. Error text is quoted from the text the Mac read, never from the model's own reading: an
    /// error the model reports is kept only when a line read from the images contains it (ignoring case and spacing),
    /// and is then written as that line.
    public static func markdown(from reply: JSONValue, readText: [String]) -> String {
        func clean(_ value: JSONValue?) -> String {
            (value?.string ?? "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        }
        func list(_ value: JSONValue?) -> [String] {
            guard case .array(let items)? = value else { return [] }
            return items.compactMap(\.string).map { $0.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var out: [String] = []
        let title = clean(reply["title"])
        out.append("## " + (title.isEmpty ? "Bug report" : title))
        let steps = list(reply["steps"]).map { step in
            // The model sometimes numbers its steps itself.
            var step = step
            if let range = step.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) { step.removeSubrange(range) }
            return step
        }
        if !steps.isEmpty {
            out.append("### Steps\n" + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        }
        let expected = clean(reply["expected"]), actual = clean(reply["actual"])
        if !expected.isEmpty { out.append("### Expected\n" + expected) }
        if !actual.isEmpty { out.append("### Actual\n" + actual) }
        let errors = verified(list(reply["errors"]), in: readText)
        if !errors.isEmpty {
            out.append("### Error text\n" + errors.map { "> " + $0 }.joined(separator: "\n"))
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    /// The lines of `readText` that contain each of `claimed`, once each, in the order claimed.
    static func verified(_ claimed: [String], in readText: [String]) -> [String] {
        func key(_ text: String) -> String {
            text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        var result: [String] = []
        for claim in claimed {
            let wanted = key(claim)
            guard wanted.count >= 3, let line = readText.first(where: { key($0).contains(wanted) }), !result.contains(line) else { continue }
            result.append(line)
        }
        return result
    }
}
