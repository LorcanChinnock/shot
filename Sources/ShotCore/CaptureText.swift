import Foundation

/// The text in a capture, as ShotCore's `TextRecognizer` reads it: lines in reading order, each with its words. Every
/// box is in the file's pixels with a top-left origin.
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

        /// Where each word of `text` is: the runs between whitespace. The recogniser boxes words by these ranges.
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
}
