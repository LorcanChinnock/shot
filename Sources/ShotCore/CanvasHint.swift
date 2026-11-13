import CoreGraphics
import Foundation

/// The hint at the image editor canvas's bottom right, from Edit › Image editor · annotate: what's selected or what the
/// tool does, then a key or two that change it, as in "Arrow selected · ⌫ delete · ⇧ snap 45°".
public struct CanvasHint: Equatable, Sendable {
    /// A key the hint offers and what it does.
    public struct Part: Equatable, Sendable {
        public let key: Key?
        public let action: String

        public init(_ key: Key?, _ action: String) {
            self.key = key
            self.action = action
        }
    }

    /// The keys a hint can name, each shown as its symbol and read to VoiceOver by its name.
    public enum Key: Sendable {
        case delete, shift, option, escape

        public var symbol: String {
            switch self {
            case .delete: "⌫"
            case .shift: "⇧"
            case .option: "⌥"
            case .escape: "esc"
            }
        }

        public var name: String {
            switch self {
            case .delete: String(localized: "Delete")
            case .shift: String(localized: "Shift")
            case .option: String(localized: "Option")
            case .escape: String(localized: "Escape")
            }
        }
    }

    /// What's selected or what the tool does, such as "Arrow selected" or "Drag to draw an arrow".
    public let lead: String
    public let parts: [Part]

    public init(_ lead: String, _ parts: [Part] = []) {
        self.lead = lead
        self.parts = parts
    }

    /// The hint as VoiceOver reads it, with each key by its name: "Arrow selected. Delete: delete. Shift: snap 45°".
    public var spoken: String {
        ([lead] + parts.map { part in part.key.map { "\($0.name): \(part.action)" } ?? part.action }).joined(separator: ". ")
    }

    /// The hint for the canvas as it is, or `nil` in crop mode, where the crop bar takes the foot and names its own keys.
    /// Typing comes first, since its key works only then. Then the selection: several marks, one locked mark, or one mark
    /// with what Shift does while you resize it. With nothing selected, the tool's action and what Shift or Option does
    /// while you draw.
    public static func hint(tool: EditorTool, selection: [Annotation], isTyping: Bool) -> CanvasHint? {
        if isTyping {
            return CanvasHint(String(localized: "Typing"), [Part(.escape, String(localized: "done"))])
        }
        if tool == .crop {
            return nil
        }
        if selection.count > 1 {
            return CanvasHint(
                String(localized: "\(selection.count) selected"),
                [Part(.delete, String(localized: "delete")), Part(.escape, String(localized: "deselect"))]
            )
        }
        if let mark = selection.first {
            if mark.isLocked {
                return CanvasHint(String(localized: "\(mark.kindTitle) locked"), [Part(nil, String(localized: "unlock it in Layers"))])
            }
            return CanvasHint(String(localized: "\(mark.kindTitle) selected"), [Part(.delete, String(localized: "delete")), resizeHint(mark.kind)])
        }
        return toolHint(tool)
    }

    /// What Shift does to a mark's handles, or Esc when it does nothing.
    private static func resizeHint(_ kind: Annotation.Kind) -> Part {
        switch kind {
        case .arrow, .line: Part(.shift, String(localized: "snap 45°"))
        case .image: Part(.shift, String(localized: "resize freely"))
        case .shape, .highlight, .pixelate, .blur, .spotlight, .freehand, .marker: Part(.shift, String(localized: "keep proportions"))
        case .text, .note, .counter: Part(.escape, String(localized: "deselect"))
        }
    }

    private static func toolHint(_ tool: EditorTool) -> CanvasHint? {
        let snap = Part(.shift, String(localized: "snap 45°"))
        let fromCentre = Part(.option, String(localized: "from centre"))
        return switch tool {
        case .select: CanvasHint(String(localized: "Click a mark to select it"))
        case .hand: CanvasHint(String(localized: "Drag to move around"))
        case .arrow: CanvasHint(String(localized: "Drag to draw an arrow"), [snap])
        case .line: CanvasHint(String(localized: "Drag to draw a line"), [snap])
        case .shape: CanvasHint(String(localized: "Drag to draw a shape"), [Part(.shift, String(localized: "equal sides")), fromCentre])
        case .pen: CanvasHint(String(localized: "Drag to draw freehand"))
        case .text: CanvasHint(String(localized: "Click to type"), [Part(nil, String(localized: "drag for a text box"))])
        case .note: CanvasHint(String(localized: "Drag to add a sticky note"))
        case .highlight: CanvasHint(String(localized: "Drag over text"), [Part(.shift, String(localized: "straight line"))])
        case .spotlight: CanvasHint(String(localized: "Drag around what matters"), [fromCentre])
        case .redact: CanvasHint(String(localized: "Drag over private details"), [fromCentre])
        case .counter: CanvasHint(String(localized: "Click to add the next step"))
        case .crop: nil
        }
    }
}

/// The zoom control at the canvas's bottom left: − · 86% · + · Fit.
public enum ZoomControl {
    /// The zoom as a whole percentage, so 0.864 shows as 86.
    public static func percent(_ zoom: CGFloat) -> Int {
        Int((zoom * 100).rounded())
    }

    /// Whether + has a step to go to, as ⌘+ does.
    public static func canZoomIn(_ zoom: CGFloat) -> Bool {
        Viewport.zoom(after: zoom) != zoom
    }

    /// Whether − has a step to go to, as ⌘− does; a fit smaller than the smallest step has none.
    public static func canZoomOut(_ zoom: CGFloat) -> Bool {
        Viewport.zoom(before: zoom) != zoom
    }
}
