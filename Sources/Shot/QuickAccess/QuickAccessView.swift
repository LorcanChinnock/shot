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

    /// The card's part of fanning out or folding, or nothing with Reduce Motion, which puts it in place at once.
    private func stackAnimation(forCardAt index: Int) -> Animation? {
        let fanningOut = model.isFannedOut
        guard let animation = Motion.animation(fanningOut ? .stackFan : .stackFold) else {
            return nil
        }
        return animation.delay(QuickAccessLayout.moveDelay(forCardAt: index, of: model.cards.count, fanningOut: fanningOut))
    }

    var body: some View {
        let layout = model.layout
        ZStack(alignment: .bottom) {
            ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                let placement = layout.placements[index]
                QuickAccessCardView(card: card, height: placement.height, isBehind: placement.isBehind, controller: controller)
                    .scaleEffect(placement.scale, anchor: .bottom)
                    .offset(y: QuickAccessLayout.padding - placement.frame.minY)
                    // Fanning out deals the older cards up one after another, and folding drops them back top first,
                    // each on its own delay. Adding or closing a card moves them together, on the controller's animation.
                    .animation(stackAnimation(forCardAt: index), value: model.isFannedOut)
                    // Cards move with the change that moved them. Reduce Motion puts them in place at once.
                    .transaction(value: placement) { transaction in
                        if Motion.reduced {
                            transaction.animation = nil
                        }
                    }
                    .zIndex(Double(index))
                    // VoiceOver reads the newest card first, as it's the one in front.
                    .accessibilitySortPriority(Double(index))
                    .transition(transition)
            }
        }
        .padding(QuickAccessLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// One capture: the picture filling a white card, with Copy, Save As… and the corner buttons over it on hover. Behind the
/// newest card, it's covered in the dark fill the board gives the cards behind.
private struct QuickAccessCardView: View {
    let card: QuickAccessCard
    let height: CGFloat
    let isBehind: Bool
    let controller: QuickAccessController
    @State private var hovering = false
    @AccessibilityFocusState private var voiceOverFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The dark cover lifts off quickly as a card rises out of the stack, so the capture shows while it moves, and
    /// settles back on only as the card lands behind the front one.
    private var coverTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.animation(.easeIn(duration: 0.12).delay(0.1)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .circular) }

    var body: some View {
        ZStack {
            picture
                .accessibilityActions { accessibilityActions }
                .accessibilityFocused($voiceOverFocused)
            if isBehind {
                FloatingPanel.cardBehind
                    .transition(coverTransition)
                    .accessibilityHidden(true)
            } else if hovering, card.confirmation == nil {
                hoverActions
                    .transition(.opacity)
            }
            if !isBehind {
                CardConfirmation(confirmation: card.confirmation)
            }
            if !isBehind, card.isVideo, let duration = card.duration {
                ThemeBadge(text: Gallery.duration(duration), style: .strong)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? Motion.fade : .spring(duration: Moment.panelArrive.duration, bounce: 0.35), value: card.confirmation?.id)
        .frame(width: QuickAccessCard.width, height: height)
        .background(Color.white)
        .clipShape(shape)
        .inkBorder(shape, width: contrast == .increased ? 1 : 0.5, color: edgeColor)
        .contentShape(shape)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : Motion.fade) {
                hovering = inside
            }
            controller.setHovering(inside, card: card.id)
        }
        .onChange(of: voiceOverFocused) { _, focused in
            controller.setVoiceOverFocus(focused, card: card.id)
        }
        .onDrag { NSItemProvider(contentsOf: card.styledURL ?? card.fileURL) ?? NSItemProvider() }
        .contextMenu { menu }
    }

    /// The board's 0.5 pt edge at 30% black; Increase Contrast takes it to 1 pt at 60%, or at 40% white on a dark card
    /// behind, as on a floating panel.
    private var edgeColor: Color {
        guard contrast == .increased else {
            return .black.opacity(0.3)
        }
        return isBehind ? .white.opacity(0.4) : .black.opacity(0.6)
    }

    /// The capture, filling the card and cropped to its middle, or whole when it's a strip too wide to crop (`ThumbnailFit`).
    /// A recording with no first frame shows a film symbol.
    @ViewBuilder
    private var picture: some View {
        let label = Text(card.isVideo ? "Recording \(card.fileURL.lastPathComponent)" : "Screenshot \(card.fileURL.lastPathComponent)")
        if card.thumbnail.isTemplate {
            Image(nsImage: card.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                // The card is white in both appearances, so the placeholder takes a fixed dark grey rather than ink.
                .foregroundStyle(ContrastAware(standard: Color(hex: 0x16161A).opacity(0.4), increased: Color(hex: 0x16161A).opacity(0.75)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(label)
        } else {
            let whole = ThumbnailFit.showsWhole(card.thumbnail.size, in: CGSize(width: QuickAccessCard.width, height: height))
            Image(nsImage: card.thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: whole ? .fit : .fill)
                .frame(width: QuickAccessCard.width, height: height)
                .clipped()
                .accessibilityLabel(label)
                .accessibilityHint(Text("Drag into any app"))
        }
    }

    /// Close and the right-click menu's actions, so VoiceOver can use a card without hovering it.
    @ViewBuilder
    private var accessibilityActions: some View {
        Button("Close") { controller.remove(card.id) }
        ForEach(Array(controller.actions(for: card).compactMap { $0 }.enumerated()), id: \.offset) { _, action in
            if action.children.isEmpty {
                Button(action.title, action: action.perform)
            }
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
                .buttonStyle(ThemeButtonStyle(.main, floating: true))
                // White over any picture, as the board draws it, in both appearances.
                Button { controller.saveAs(card) } label: {
                    Text("Save As…")
                        .font(.scaled(14, weight: .medium))
                        .frame(minWidth: 104)
                        // As tall as Copy, whose floating style pads it more.
                        .padding(.vertical, 3)
                }
                .buttonStyle(ThemeButtonStyle())
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

/// "Copied" over the card for a moment: the scrim, and a dark pill led by the accent tick that pops in and draws itself.
/// It takes the hover buttons' place while it shows, and lets clicks through to the card.
private struct CardConfirmation: View {
    let confirmation: ActionConfirmation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let confirmation {
                FloatingPanel.scrim
                    .transition(.opacity)
                pill(confirmation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pill(_ confirmation: ActionConfirmation) -> some View {
        HStack(spacing: 8) {
            TickMark(draws: true)
            Text(confirmation.message)
                .font(.scaled(14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: 36)
        .floatingPanel(Capsule(), opacity: FloatingPanel.Opacity.toast)
        .id(confirmation.id)
        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.5).combined(with: .opacity), removal: .scale(scale: 0.9).combined(with: .opacity)))
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
        .themeTip(help)
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
