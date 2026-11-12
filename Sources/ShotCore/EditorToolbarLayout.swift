import CoreGraphics
import Foundation

/// What the image editor's title bar holds, from Edit › Image editor · annotate: one group of tools, then the Share menu.
public enum EditorToolbarLayout {
    /// The tools before the group's divider, in order. Add image and Crop follow the divider. The hand tool has no
    /// button: H, Space-drag, a middle-drag and scrolling still move around.
    public static let drawingTools: [EditorTool] = [.select, .arrow, .line, .shape, .pen, .text, .note, .highlight, .spotlight, .redact, .counter]

    /// The tools after the divider, after Add image.
    public static let afterDivider: [EditorTool] = [.crop]

    /// Every tool with a button in the group.
    public static var groupedTools: [EditorTool] { drawingTools + afterDivider }

    /// The tool shown as selected, if it has a button: none while the hand tool is in use.
    public static func selectedButton(for tool: EditorTool) -> EditorTool? {
        groupedTools.contains(tool) ? tool : nil
    }

    /// "1,040 × 600": the size the image exports at, in pixels, as the title bar shows it under the file name.
    public static func sizeLabel(_ size: CGSize, locale: Locale = .current) -> String {
        let style = IntegerFormatStyle<Int>(locale: locale).grouping(.automatic)
        let width = Int(size.width.rounded()).formatted(style)
        let height = Int(size.height.rounded()).formatted(style)
        return "\(width) × \(height)"
    }
}

/// The image editor's Share menu, in order.
public enum EditorShareAction: CaseIterable, Sendable {
    case copyImage, copyPath, saveAs, showInFinder, pin

    /// Whether a divider comes before it in the menu: the copies, then the file, as on the board.
    public var startsSection: Bool { self == .saveAs }

    /// The key shown beside it. Only Copy Image has one: ⌘C, as the Copy button.
    public var shortcut: String? { self == .copyImage ? "⌘C" : nil }

    /// Whether the editor saves unsaved changes before doing it, so the file it hands on has them. Copy Path and Show in
    /// Finder point at the file, so an edit not yet saved would be missing from what someone opens.
    public func savesFirst(isDirty: Bool) -> Bool {
        isDirty && (self == .copyPath || self == .showInFinder)
    }
}
