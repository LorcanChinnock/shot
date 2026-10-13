import Foundation

/// What Shot records inside a capture for AI agents, once the Agents setting is on: where it came from and what was
/// marked on it. It's a stable, versioned schema of its own, not the editor's internal encoding, so agents can rely on it
/// while the editor's model changes, and a mark carries enough to rebuild it as a live annotation. Coordinates are in
/// the saved file's pixels, with the origin at the top left.
public struct CaptureRecord: Codable, Equatable, Sendable {
    /// `shot.capture/1` was a `.shot.json` beside the file; it decodes as this too, with `file` ignored.
    public static let currentSchema = "shot.capture/2"
    public static let coordinateSpaceDescription = "image pixels, top-left origin"

    public struct Size: Codable, Equatable, Sendable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public struct Frame: Codable, Equatable, Sendable {
        public var x, y, width, height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// What was captured. Window titles can be private, which is one reason the record is opt-in.
    public struct Source: Codable, Equatable, Sendable {
        /// "area", "window" or "fullscreen".
        public var mode: String
        public var app: String?
        public var bundleID: String?
        public var windowTitle: String?
        /// Where it was on screen, in points of the global CoreGraphics space: the origin at the top left of the main
        /// display, y growing downwards, as `CGWindowListCopyWindowInfo` reports window bounds.
        public var screenFrame: Frame?

        public init(mode: String, app: String? = nil, bundleID: String? = nil, windowTitle: String? = nil, screenFrame: Frame? = nil) {
            self.mode = mode
            self.app = app
            self.bundleID = bundleID
            self.windowTitle = windowTitle
            self.screenFrame = screenFrame
        }
    }

    public var schema: String
    /// The capture an edited version was saved from, by name, since it sits beside it; `nil` for the capture itself.
    public var original: String?
    /// "image" or "video".
    public var kind: String
    /// To the second.
    public var created: Date
    public var size: Size
    /// Pixels per point of the screen it was captured on.
    public var scale: Double
    public var source: Source?
    /// The part of `original` this version shows, as [x, y, width, height] in the original's pixels: a crop, or past its
    /// edges for padding. The marks are offset from its origin.
    public var canvas: [Double]?
    /// Set when the version is a crop of `original`: the crop, in the same pixels as `canvas`, so Shot reopens it with
    /// the crop still adjustable.
    public var crop: [Double]?
    /// True when the marks rebuild every layer of the version exactly, so Shot reopens it as `original` with them live
    /// rather than flattened.
    public var editable: Bool?
    public var coordinateSpace: String
    public var annotations: [CaptureMark]

    public init(original: String? = nil, kind: String, created: Date, size: Size, scale: Double, source: Source? = nil, canvas: [Double]? = nil, crop: [Double]? = nil, editable: Bool? = nil, annotations: [CaptureMark] = []) {
        schema = Self.currentSchema
        self.original = original
        self.kind = kind
        self.created = Date(timeIntervalSince1970: created.timeIntervalSince1970.rounded(.down))
        self.size = size
        self.scale = scale
        self.source = source
        self.canvas = canvas
        self.crop = crop
        self.editable = editable
        coordinateSpace = Self.coordinateSpaceDescription
        self.annotations = annotations
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> CaptureRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CaptureRecord.self, from: data)
    }

    /// The record as an agent reads it in a tool result: a few plain lines rather than the JSON, with each mark's
    /// position in the file's pixels. Empty when there's nothing to say.
    public var summaryLines: [String] {
        var lines: [String] = []
        if let source {
            let what = source.app.map { app in source.windowTitle.map { "\(app), window \"\($0)\"" } ?? app }
            lines.append("Captured from: \(what ?? "the screen") (\(source.mode) capture).")
        }
        if let original {
            lines.append("Saved in Shot's editor from \(original), which is in the same folder.")
        }
        let notes = annotations.filter { $0.type == "note" }.compactMap(\.text)
        if !notes.isEmpty {
            lines.append("The user's notes: " + notes.map { "\"\($0)\"" }.joined(separator: ", ") + ".")
        }
        let redacted = annotations.filter { ["blur", "pixelate"].contains($0.type) }.count
        if redacted > 0 {
            lines.append("\(redacted) \(redacted == 1 ? "area is" : "areas are") redacted on purpose: don't try to read or guess what's under \(redacted == 1 ? "it" : "them").")
        }
        if !annotations.isEmpty {
            lines.append("What the user marked, in the file's pixels (top-left origin):")
            lines += annotations.map { "- " + $0.summary }
        }
        return lines
    }
}

/// One mark on a capture, in the saved file's pixels. Only the fields its `type` uses are set. The fields from
/// `lineWidth` on are there to rebuild the mark in the editor; an agent can leave them out.
public struct CaptureMark: Codable, Equatable, Sendable {
    /// Unique within the record; marks an agent writes may leave it out.
    public var id: String?
    /// arrow, line, rectangle, rounded, ellipse, triangle, diamond, star, highlight, blur, pixelate, spotlight, text,
    /// counter, note, pen, marker or image.
    public var type: String
    /// An arrow's or line's ends, as [x, y].
    public var from: [Double]?
    public var to: [Double]?
    /// [x, y, width, height]. A text's top left is its origin.
    public var rect: [Double]?
    /// A counter's centre, as [x, y].
    public var center: [Double]?
    /// A pen or marker stroke, as [[x, y], …].
    public var points: [[Double]]?
    /// What a text or note says.
    public var text: String?
    /// A counter's number.
    public var number: Int?
    /// The nearest palette colour's name, such as "red", which agents reason about better than a hex.
    public var color: String?
    /// `#RRGGBB`, plus the alpha when it isn't opaque.
    public var hex: String?
    /// A word for the agent, such as that a redaction hides what's under it.
    public var note: String?
    public var lineWidth: Double?
    /// A shape's fill, as a hex.
    public var fill: String?
    public var fontSize: Double?
    /// A blur's or pixelation's strength, as a fraction of the image's longer side.
    public var amount: Double?
    /// How far a curved arrow or line bows from straight, as [dx, dy].
    public var bend: [Double]?
    public var cornerRadius: Double?

    public init(
        id: String? = nil, type: String, from: [Double]? = nil, to: [Double]? = nil, rect: [Double]? = nil, center: [Double]? = nil,
        points: [[Double]]? = nil, text: String? = nil, number: Int? = nil, color: String? = nil, hex: String? = nil, note: String? = nil,
        lineWidth: Double? = nil, fill: String? = nil, fontSize: Double? = nil, amount: Double? = nil, bend: [Double]? = nil, cornerRadius: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.from = from
        self.to = to
        self.rect = rect
        self.center = center
        self.points = points
        self.text = text
        self.number = number
        self.color = color
        self.hex = hex
        self.note = note
        self.lineWidth = lineWidth
        self.fill = fill
        self.fontSize = fontSize
        self.amount = amount
        self.bend = bend
        self.cornerRadius = cornerRadius
    }

    /// One line for `CaptureRecord.summaryLines`, such as `arrow from (410, 220) to (612, 388), red`.
    var summary: String {
        func format(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        }
        func point(_ p: [Double]?) -> String? {
            guard let p, p.count == 2 else { return nil }
            return "(\(format(p[0])), \(format(p[1])))"
        }
        func box(_ r: [Double]?) -> String? {
            guard let r, r.count == 4 else { return nil }
            return "at (\(format(r[0])), \(format(r[1]))), \(format(r[2]))×\(format(r[3]))"
        }
        var parts = [type]
        if let text {
            parts.append("\"\(text)\"")
        }
        if let number {
            parts.append(String(number))
        }
        if let from = point(from), let to = point(to) {
            parts.append("from \(from) to \(to)")
        } else if let center = point(center) {
            parts.append("at \(center)")
        } else if let box = box(rect) {
            parts.append(box)
        }
        var line = parts.joined(separator: " ")
        if let color {
            line += ", \(color)"
        }
        if let note {
            line += " (\(note))"
        }
        return line
    }
}
