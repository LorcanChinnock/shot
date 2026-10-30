import Foundation

/// What the editor's crop tool does with the rectangle being adjusted, in the image's pixels.
public enum CropEditing {
    public enum Outcome: Equatable, Sendable {
        case nothing
        case cropImage(UUID, CGRect)
        case cropFrame(CGRect)
    }

    /// The tool to go back to when the crop tool is put down; picking it again from itself leaves for select.
    public static func toolBefore(taking previous: EditorTool) -> EditorTool {
        previous == .crop ? .select : previous
    }

    /// The crop to start adjusting: the placed image's bounds, else the frame crop, else all of the content.
    public static func startingDraft(imageBounds: CGRect?, frameCrop: CGRect?, contentRect: CGRect) -> CGRect {
        imageBounds ?? frameCrop ?? contentRect
    }

    /// What putting the tool down changes. A placed image is cropped when the draft differs from its bounds; the frame
    /// when the draft differs from its current crop (rounded to whole pixels), or the crop is hidden and applying brings it back.
    public static func outcome(draft: CGRect, image: (id: UUID, bounds: CGRect?)?, frameCrop: CGRect?, contentRect: CGRect, isFrameCropHidden: Bool) -> Outcome {
        if let image {
            guard let current = image.bounds, draft != current else {
                return .nothing
            }
            return .cropImage(image.id, draft)
        }
        guard draft.integral != (frameCrop ?? contentRect) || isFrameCropHidden else {
            return .nothing
        }
        return .cropFrame(draft)
    }

    /// The draft after a shape is picked: the largest crop of that shape inside the current one; free leaves it as it is.
    public static func draft(_ draft: CGRect, holding aspect: CropAspect) -> CGRect {
        guard let ratio = aspect.ratio(for: draft.size) else {
            return draft
        }
        return CropGeometry.fit(ratio: ratio, in: draft)
    }

    /// Whether Reset has a crop to take off. `fullRect` is where a placed image being cropped would be drawn whole.
    public static func canReset(draft: CGRect?, fullRect: CGRect?, contentRect: CGRect, hasFrameCrop: Bool) -> Bool {
        if let fullRect {
            return draft.map { $0 != fullRect } ?? false
        }
        return draft.map { $0 != contentRect } ?? hasFrameCrop
    }

    /// The draft Reset puts back while the tool is active: the whole image, else all of the content.
    public static func resetDraft(fullRect: CGRect?, contentRect: CGRect) -> CGRect {
        fullRect ?? contentRect
    }
}
