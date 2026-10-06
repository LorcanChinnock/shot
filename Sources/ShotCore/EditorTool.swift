import CoreGraphics

public enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case select, arrow, line, rect, ellipse, pen, text, note, highlight, spotlight, pixelate, blur, counter, crop

    public var id: String { rawValue }

    public var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rect: "r"
        case .ellipse: "o"
        case .pen: "d"
        case .text: "t"
        case .note: "s"
        case .highlight: "h"
        case .spotlight: "f"
        case .pixelate: "p"
        case .blur: "b"
        case .counter: "n"
        case .crop: "c"
        }
    }

    public var title: String { rawValue.capitalized }

    /// False for select and crop, which an editor never starts with.
    public var isDrawing: Bool { self != .select && self != .crop }
}

/// The tool, colours and width a new editor window starts with: the last ones used.
public struct EditorStyle: Equatable, Sendable {
    /// Line widths in points; the image's scale multiplies them.
    public static let widths: [CGFloat] = [2, 4, 8]

    public var tool: EditorTool
    public var color: RGBA
    /// Notes keep their own colour, pale yellow until the user picks another.
    public var noteColor: RGBA
    /// What new rectangles and ellipses are filled with; `nil` leaves them unfilled.
    public var fill: RGBA?
    /// Index into `widths`.
    public var widthIndex: Int
    /// Custom colours picked lately, newest first.
    public var recentColors: [RGBA]

    public static let maxRecentColors = 6

    public init(
        tool: EditorTool = .arrow, color: RGBA = RGBA.presets[0], noteColor: RGBA = RGBA.presets[2],
        fill: RGBA? = nil, widthIndex: Int = 1, recentColors: [RGBA] = []
    ) {
        self.tool = tool
        self.color = color
        self.noteColor = noteColor
        self.fill = fill
        self.widthIndex = widthIndex
        self.recentColors = recentColors
    }

    /// `recentColors` with `color` first, unless it's a preset.
    public static func recents(adding color: RGBA, to recents: [RGBA]) -> [RGBA] {
        guard !RGBA.presets.contains(color) else {
            return recents
        }
        return Array(([color] + recents.filter { $0 != color }).prefix(maxRecentColors))
    }
}
