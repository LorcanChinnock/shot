import AppKit
import ShotCore
import SwiftUI

struct QuickAccessView: View {
    let model: QuickAccessModel
    let controller: QuickAccessController
    @Setting(PreferenceKey.quickAccessPosition) private var position: QuickAccessPosition

    private var edge: Edge { position == .right ? .trailing : .leading }

    private var transition: AnyTransition {
        guard !Motion.reduced else {
            return .opacity
        }
        let anchor: UnitPoint = edge == .trailing ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .scale(scale: 0.88, anchor: anchor)).combined(with: .opacity),
            removal: .move(edge: edge).combined(with: .scale(scale: 0.94, anchor: anchor)).combined(with: .opacity)
        )
    }

    var body: some View {
        VStack(spacing: QuickAccessLayout.spacing) {
            ForEach(model.cards) { card in
                QuickAccessCardView(card: card, controller: controller)
                    .transition(transition)
            }
        }
        .padding(QuickAccessLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// One capture: the picture filling a white card, with Copy, Save As… and the corner buttons over it on hover.
private struct QuickAccessCardView: View {
    let card: QuickAccessCard
    let controller: QuickAccessController
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Brutal.Radius.panel, style: .circular) }

    var body: some View {
        ZStack {
            picture
            if hovering {
                hoverActions
                    .transition(.opacity)
            }
            if card.isVideo, let duration = card.duration {
                BrutalBadge(text: Gallery.duration(duration), style: .strong)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: QuickAccessCard.width, height: card.height)
        .background(Color.white)
        .clipShape(shape)
        // The board's 0.5 pt edge at 30% black; Increase Contrast takes it to 1 pt at 60%.
        .inkBorder(shape, width: contrast == .increased ? 1 : 0.5, color: .black.opacity(contrast == .increased ? 0.6 : 0.3))
        .contentShape(shape)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : Motion.fade) {
                hovering = inside
            }
            controller.setHovering(inside, card: card.id)
        }
        .onDrag { NSItemProvider(contentsOf: card.styledURL ?? card.fileURL) ?? NSItemProvider() }
        .contextMenu { menu }
    }

    /// The capture, filling the card and cropped to its middle. A recording with no first frame shows a film symbol.
    @ViewBuilder
    private var picture: some View {
        let label = Text(card.isVideo ? "Recording \(card.fileURL.lastPathComponent)" : "Screenshot \(card.fileURL.lastPathComponent)")
        if card.thumbnail.isTemplate {
            Image(nsImage: card.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Brutal.ink.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(label)
        } else {
            Image(nsImage: card.thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: QuickAccessCard.width, height: card.height)
                .clipped()
                .accessibilityLabel(label)
                .accessibilityHint(Text("Drag into any app"))
        }
    }

    /// The hover buttons' actions again, plus Copy Path and Show in Finder, which have no button: the card stays as
    /// plain as it is.
    private var menu: some View {
        ForEach(Array(controller.actions(for: card).enumerated()), id: \.offset) { _, action in
            if let action, !action.children.isEmpty {
                Menu(action.title) {
                    ForEach(Array(action.children.enumerated()), id: \.offset) { _, child in
                        Button(child.title, action: child.perform)
                    }
                }
            } else if let action {
                Button(action.title, action: action.perform)
            } else {
                Divider()
            }
        }
    }

    private var hoverActions: some View {
        ZStack {
            // Dimmed rather than blurred, so the screenshot still shows behind the buttons.
            FloatingPanel.scrim
            VStack(spacing: 8) {
                Button { controller.copy(card) } label: {
                    Text("Copy")
                        .font(.scaled(14, weight: .semibold))
                        .frame(minWidth: 104)
                }
                .buttonStyle(BrutalButtonStyle(.main, floating: true))
                // White over any picture, as the board draws it, in both appearances.
                Button { controller.saveAs(card) } label: {
                    Text("Save As…")
                        .font(.scaled(14, weight: .medium))
                        .frame(minWidth: 104)
                        // As tall as Copy, whose floating style pads it more.
                        .padding(.vertical, 3)
                }
                .buttonStyle(BrutalButtonStyle())
                .environment(\.colorScheme, .light)
            }
            VStack {
                HStack(spacing: 6) {
                    CornerButton(symbol: "xmark", help: "Close", iconSize: 10) { controller.remove(card.id) }
                    Spacer()
                    if card.isVideo {
                        CornerButton(symbol: "scissors", help: "Edit Video", iconSize: 12) { controller.annotate(card) }
                        CornerButton(symbol: "photo.stack", help: "Export GIF", iconSize: 12) { controller.exportGIF(card) }
                    } else {
                        CornerButton(symbol: "pencil", help: "Annotate", iconSize: 12) { controller.annotate(card) }
                    }
                }
                Spacer()
                HStack(alignment: .bottom) {
                    DragChip()
                    Spacer()
                    // A recording's length badge sits here instead.
                    if !card.isVideo {
                        CornerButton(symbol: "pin", help: "Pin to Screen", iconSize: 12) { controller.pin(card) }
                    }
                }
            }
            .padding(8)
        }
    }
}

/// "Drag into any app", in the card's bottom-left corner on hover. The card itself is what you drag.
private struct DragChip: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 10, weight: .bold))
            Text("Drag into any app")
                .font(.scaled(10.5))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .floatingPanel(Capsule(), opacity: FloatingPanel.Opacity.cornerButton)
        .padding(2)
        .accessibilityHidden(true)
    }
}

struct CornerButton: View {
    let symbol: String
    let help: LocalizedStringResource
    var iconSize: CGFloat = 11
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .bold))
        }
        .buttonStyle(CornerButtonStyle())
        .brutalTip(help)
        .accessibilityLabel(Text(help))
    }
}

/// A small round floating panel over a capture, with a white icon. It brightens while pressed.
private struct CornerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .overlay {
                if configuration.isPressed {
                    Circle().fill(.white.opacity(0.16))
                }
            }
            .floatingPanel(Circle(), opacity: FloatingPanel.Opacity.cornerButton)
            .contentShape(Circle())
    }
}
