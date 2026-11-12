import ShotCore
import SwiftUI

/// What the style sections edit: the image editor's selection or screenshot in its Style panel, or the video editor's
/// selected clip or annotation in its Inspector. Sizes are in points, which `scale` turns into the target's pixels.
@MainActor
protocol StyleEditing: AnyObject, Observable {
    var targetStyleKind: StyleKind? { get }
    var targetHasTransparency: Bool { get }
    /// Whether the target is a window captured with the macOS shadow, which takes no shadow of its own.
    var targetHasWindowShadow: Bool { get }
    var targetStyle: ObjectStyle { get }
    var targetCornerRadius: CGFloat { get }
    var scale: CGFloat { get }
    /// A style the pointer is on, shown in place of the target's until it moves off.
    var stylePreview: ObjectStyle? { get set }
    /// The colour last picked for a border in the custom colour editor; `nil` until one is.
    var lastBorderColor: RGBA? { get }
    func newBorder(_ kind: Border.Kind) -> Border
    func setTargetStyle(_ style: ObjectStyle)
    func setShadowElevation(_ points: CGFloat)
    func setShadowOpacity(_ opacity: CGFloat)
    func setBorderWidth(_ points: CGFloat)
    func setBorderColor(_ color: RGBA)
    func pickBorderColor(_ color: RGBA)
    func setTargetCornerRadius(_ points: CGFloat)
    /// Puts the target's shadow, border and corners back to how a new one of its kind starts, as one undo step, and
    /// remembers that for the next one.
    func resetTargetStyle()
    func setDraggingStyle(_ dragging: Bool)
    /// Whether new captures get the screenshot's style; `nil` hides the switch, as the video editor has no screenshot.
    var newCaptureStyle: Binding<Bool>? { get }
    /// Whether new captures get a saved style other than this screenshot's, so the switch is off but they're still styled.
    var newCapturesHaveOtherStyle: Bool { get }
    /// Call as the colour editor opens, so its picks start a new undo step.
    func beginColorPick()
}

extension StyleEditing {
    var targetHasWindowShadow: Bool { false }
    var newCaptureStyle: Binding<Bool>? { nil }
    var newCapturesHaveOtherStyle: Bool { false }
}

/// The style Copy Style took last, in any editor window, photo or video, which Paste Style puts on the selection.
@MainActor
enum StyleClipboard {
    static var copied: CopiedStyle?
}

extension EditorModel: StyleEditing {
    var newCaptureStyle: Binding<Bool>? {
        Binding(get: { self.usesStyleForNewCaptures }, set: { self.setUsesStyleForNewCaptures($0) })
    }
}

extension Border.Kind {
    var title: String {
        switch self {
        case .hairline: String(localized: "Hairline")
        case .solid: String(localized: "Solid")
        case .outline: String(localized: "Outline")
        }
    }
}

/// A white card with a preset's shadow or border, as a tile's picture; an outline's is a cut-out disc with a white rim.
struct StylePresetSwatch: View {
    var shadow: ShadowPreset?
    var border: Border.Kind?

    var body: some View {
        let card = RoundedRectangle(cornerRadius: Theme.Radius.tiny, style: .circular)
        if border == .outline {
            Circle().fill(Theme.sky)
                .padding(3)
                .background(Circle().fill(.white))
                .overlay(Circle().stroke(Theme.line.opacity(0.45), lineWidth: 1))
                .frame(width: 16, height: 16)
        } else {
            card.fill(.white)
                .overlay {
                    switch border {
                    case .hairline: card.stroke(Theme.line.opacity(0.45), lineWidth: 1)
                    case .solid: card.stroke(Theme.sky, lineWidth: 3)
                    case .outline, nil: EmptyView()
                    }
                }
                .shadow(color: color, radius: radius, y: offset)
        }
    }

    private var color: Color {
        switch shadow {
        case nil: .clear
        case .glow: Theme.sky
        case .contact: .black.opacity(0.45)
        case .soft, .float: .black.opacity(0.3)
        }
    }

    private var radius: CGFloat {
        switch shadow {
        case nil: 0
        case .contact: 1
        case .soft: 2.5
        case .float, .glow: 4
        }
    }

    private var offset: CGFloat {
        switch shadow {
        case nil, .glow: 0
        case .contact: 1
        case .soft: 2
        case .float: 4
        }
    }
}
