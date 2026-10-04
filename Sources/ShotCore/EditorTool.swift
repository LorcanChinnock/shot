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
    /// Indexes into `RGBA.presets`.
    public var colorIndex: Int
    /// Notes keep their own colour, pale yellow until the user picks another.
    public var noteColorIndex: Int
    /// Index into `widths`.
    public var widthIndex: Int

    public init(tool: EditorTool = .arrow, colorIndex: Int = 0, noteColorIndex: Int = 2, widthIndex: Int = 1) {
        self.tool = tool
        self.colorIndex = colorIndex
        self.noteColorIndex = noteColorIndex
        self.widthIndex = widthIndex
    }
}
