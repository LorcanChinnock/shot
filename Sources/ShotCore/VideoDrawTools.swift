import Foundation

/// The column of drawing tools beside the video while Draw is on, from Edit › Video editor and export: every tool the
/// image editor's group has, in its order, then Add image, a divider and Crop video. The hand tool has no button, since
/// the video doesn't pan.
public enum VideoDrawTools {
    public enum Button: Hashable, Sendable {
        case tool(EditorTool)
        case addImage
        case cropVideo
    }

    /// The buttons before the divider, top to bottom.
    public static let drawing: [Button] = EditorToolbarLayout.drawingTools.map(Button.tool) + [.addImage]

    /// The buttons after the divider.
    public static let afterDivider: [Button] = [.cropVideo]

    public static var all: [Button] { drawing + afterDivider }

    /// The key a button's tip shows. Only Crop video has one: C, which crops in the video editor as it always has. The
    /// drawing tools take no letter keys here, since S splits, T shows the tracks and N turns snapping on and off.
    public static func key(for button: Button) -> String? {
        button == .cropVideo ? "C" : nil
    }

    /// The button drawn as selected: Crop video while cropping, otherwise the drawing tool in use.
    public static func selected(tool: EditorTool?, cropping: Bool) -> Button? {
        if cropping {
            return .cropVideo
        }
        guard let tool, all.contains(.tool(tool)) else {
            return nil
        }
        return .tool(tool)
    }
}
