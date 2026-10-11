import Foundation

/// What `<capture>.shot.json` says about a capture, for AI agents: where it came from and what was marked on it.
/// This is a stable, versioned schema of its own, not the editor's internal encoding, so agents can rely on it while
/// the editor's model changes. Coordinates are in the saved file's pixels, with the origin at the top left.
public struct CaptureSidecar: Codable, Equatable, Sendable {
    public static let currentSchema = "shot.capture/1"
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

    /// What was captured. Window titles can be private, which is one reason the whole file is opt-in.
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
    /// The file this describes, by name, since it sits next to it.
    public var file: String
    /// The capture an edited version was saved from; `nil` for the capture itself.
    public var original: String?
    /// "image" or "video".
    public var kind: String
    /// To the second, as the file writes it.
    public var created: Date
    public var size: Size
    /// Pixels per point of the screen it was captured on.
    public var scale: Double
    public var source: Source?
    public var coordinateSpace: String
    public var annotations: [SidecarAnnotation]

    public init(file: String, original: String? = nil, kind: String, created: Date, size: Size, scale: Double, source: Source? = nil, annotations: [SidecarAnnotation] = []) {
        schema = Self.currentSchema
        self.file = file
        self.original = original
        self.kind = kind
        self.created = Date(timeIntervalSince1970: created.timeIntervalSince1970.rounded(.down))
        self.size = size
        self.scale = scale
        self.source = source
        coordinateSpace = Self.coordinateSpaceDescription
        self.annotations = annotations
    }

    /// Where the file for `capture` goes: next to it, named after it with `.shot.json` added, so an agent finds it from
    /// the capture's path alone.
    public static func url(for capture: URL) -> URL {
        capture.deletingLastPathComponent().appendingPathComponent(capture.lastPathComponent + ".shot.json")
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> CaptureSidecar {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CaptureSidecar.self, from: data)
    }
}

/// One mark on a capture, in the saved file's pixels. Only the fields its `type` uses are set.
public struct SidecarAnnotation: Codable, Equatable, Sendable {
    public var id: String
    /// arrow, line, rectangle, rounded, ellipse, triangle, diamond, star, highlight, blur, pixelate, spotlight, text,
    /// counter, note, pen, marker or image.
    public var type: String
    /// An arrow's or line's ends, as [x, y].
    public var from: [Double]?
    public var to: [Double]?
    /// [x, y, width, height].
    public var rect: [Double]?
    /// A counter's centre, as [x, y].
    public var center: [Double]?
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

    public init(id: String, type: String, from: [Double]? = nil, to: [Double]? = nil, rect: [Double]? = nil, center: [Double]? = nil, text: String? = nil, number: Int? = nil, color: String? = nil, hex: String? = nil, note: String? = nil) {
        self.id = id
        self.type = type
        self.from = from
        self.to = to
        self.rect = rect
        self.center = center
        self.text = text
        self.number = number
        self.color = color
        self.hex = hex
        self.note = note
    }
}
