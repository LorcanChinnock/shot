import CoreGraphics
import Foundation

/// The prompt **Send to Agent** opens a coding agent with: the saved file's path and a short summary of what the user
/// marked, with each mark tied to the text under it. Tested against real agents (#493): the path plus a few plain lines
/// works best. The full record makes an agent reason from coordinates and skip opening the image, so this stays to
/// about 900 characters and 10 marks.
public struct AgentPrompt: Equatable, Sendable {
    /// The most marks listed; the rest are counted.
    public static let maxMarks = 10
    /// Marks stop being listed once the prompt reaches this many characters, before the user's notes.
    static let maxLength = 900
    /// The longest a quoted piece of text gets before it's cut short with "…".
    static let maxQuote = 40

    /// The flattened file Shot saved, never the unmarked original, which would show what the user blurred.
    public var path: String
    /// What Shot wrote in the file, or `nil` when the capture record is off, which leaves just the path.
    public var record: CaptureRecord?
    /// The text Shot read in the file, to say what each mark points at.
    public var text: CaptureText?
    /// Whether Shot's MCP server is set up for the agent, so it can call `find_text`.
    public var findText: Bool

    public init(path: String, record: CaptureRecord? = nil, text: CaptureText? = nil, findText: Bool = false) {
        self.path = path
        self.record = record
        self.text = text
        self.findText = findText
    }

    public var string: String {
        lines.joined(separator: "\n")
    }

    var lines: [String] {
        let opening = ["Screenshot from Shot: \(path)", "Open the image first; the user's marks are drawn on it."]
        guard let record else {
            return opening
        }
        let notes = record.annotations.filter { $0.type == "note" }.compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var lines = notes.isEmpty ? ["Here's a screenshot I marked up:"] : notes
        lines += opening
        var about = "\(record.size.width)×\(record.size.height) px, 1 pt = \(Self.format(record.scale)) px."
        if let source = record.source, let app = source.app {
            let window = source.windowTitle.map { ", window \"\(Self.quote($0))\"" } ?? ""
            about = "Captured from \(app)\(window). " + about
        }
        lines.append(about)
        let redactions = record.annotations.filter(\.isRedaction)
        let marks = record.annotations.filter { !$0.isRedaction && $0.type != "note" }
        if !marks.isEmpty {
            lines.append("What the user marked (pixels, top-left origin):")
            let readable = readableLines(hiddenBy: redactions)
            var length = lines.dropFirst(notes.count).reduce(0) { $0 + $1.count + 1 }
            var listed = 0
            for mark in marks.prefix(Self.maxMarks) {
                let line = "- " + describe(mark, readable: readable)
                guard listed == 0 || length + line.count <= Self.maxLength else { break }
                lines.append(line)
                length += line.count + 1
                listed += 1
            }
            if marks.count > listed {
                lines.append("- and \(marks.count - listed) more")
            }
        }
        if !redactions.isEmpty {
            let count = redactions.count
            lines.append("\(count) \(count == 1 ? "area is" : "areas are") blurred on purpose; don't try to read what's under \(count == 1 ? "it" : "them").")
        }
        if findText {
            lines.append("For the text in the capture, call Shot's \(AgentTools.findText) with this path.")
        }
        return lines
    }

    /// The lines of text not under a blur or pixelation, so no mark quotes what the user hid.
    private func readableLines(hiddenBy redactions: [CaptureMark]) -> [CaptureText.Line] {
        let hidden = redactions.compactMap { Self.rect($0.rect) }
        return (text?.lines ?? []).filter { line in !hidden.contains { $0.intersects(line.box) } }
    }

    private func describe(_ mark: CaptureMark, readable: [CaptureText.Line]) -> String {
        var line: String
        var near: (String, String)?
        let box = Self.rect(mark.rect)
        switch mark.type {
        case "arrow", "line":
            let from = Self.point(mark.from), to = Self.point(mark.to)
            line = mark.type
            if let from, let to {
                line += " from \(Self.format(from)) to \(Self.format(to))"
                if mark.type == "arrow" {
                    near = Self.text(at: to, in: readable).map { ("pointing at", $0) }
                }
            }
        case "counter":
            line = "number \(mark.number ?? 1)"
            if let center = Self.point(mark.center) {
                line += " at \(Self.format(center))"
                near = Self.text(at: center, in: readable).map { ("on", $0) }
            }
        case "text":
            line = "text \"\(Self.quote(mark.text ?? ""))\""
            if let box {
                line += " at \(Self.format(box.origin))"
            }
        default:
            line = Self.names[mark.type] ?? mark.type
            if let box {
                line += " at \(Self.format(box.origin)), \(Self.format(box.width))×\(Self.format(box.height))"
                near = Self.text(inside: box, in: readable).map { (mark.type == "highlight" || mark.type == "marker" ? "over" : "around", $0) }
            }
        }
        if let color = mark.color {
            line += ", \(color)"
        }
        if let note = mark.note {
            line += " (\(note))"
        }
        if let (word, text) = near {
            line += ", \(word) \"\(text)\""
        }
        return line
    }

    /// What a mark type is called in the prompt, where its record name reads oddly.
    private static let names = ["rounded": "rectangle", "pen": "pen stroke", "marker": "marker stroke", "image": "placed image"]

    /// The line the point is on, or the nearest one within its height (at least 20 px), since an arrow's tip often
    /// stops just short of what it points at.
    static func text(at point: CGPoint, in lines: [CaptureText.Line]) -> String? {
        func distance(_ box: CGRect) -> CGFloat {
            let dx = max(box.minX - point.x, 0, point.x - box.maxX), dy = max(box.minY - point.y, 0, point.y - box.maxY)
            return (dx * dx + dy * dy).squareRoot()
        }
        let nearest = lines.map { ($0, distance($0.box)) }.filter { $0.1 <= max($0.0.box.height, 20) }.min { $0.1 < $1.1 }
        return nearest.map { quote($0.0.text) }
    }

    /// The lines at least half inside `box`, in reading order.
    static func text(inside box: CGRect, in lines: [CaptureText.Line]) -> String? {
        let inside = lines.filter { line in
            let overlap = line.box.intersection(box)
            return !overlap.isNull && overlap.width * overlap.height * 2 >= line.box.width * line.box.height
        }
        return inside.isEmpty ? nil : quote(inside.map(\.text).joined(separator: " "))
    }

    /// `text` on one line, cut to `maxQuote` characters, with its double quotes made single so the quoting stays clear.
    static func quote(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").replacingOccurrences(of: "\"", with: "'")
        return flat.count > maxQuote ? flat.prefix(maxQuote - 1).trimmingCharacters(in: .whitespaces) + "…" : flat
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func format(_ value: CGFloat) -> String {
        format(Double(value))
    }

    static func format(_ point: CGPoint) -> String {
        "(\(format(point.x)), \(format(point.y)))"
    }

    static func point(_ p: [Double]?) -> CGPoint? {
        guard let p, p.count == 2 else { return nil }
        return CGPoint(x: p[0], y: p[1])
    }

    static func rect(_ r: [Double]?) -> CGRect? {
        guard let r, r.count == 4 else { return nil }
        return CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
    }
}

extension CaptureMark {
    /// A blur or pixelation, which hides what's under it.
    var isRedaction: Bool {
        type == "blur" || type == "pixelate"
    }
}
