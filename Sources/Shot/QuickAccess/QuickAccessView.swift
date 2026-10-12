import AppKit
import ShotCore
import SwiftUI

enum QuickAccessMotion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// A soft, slightly overshooting settle as a card arrives.
    static var enter: Animation { reduced ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.72) }
    /// Quicker and without bounce, so dismissing feels responsive; neighbours slide into the gap with the same curve.
    static var exit: Animation { reduced ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.9) }
}

struct QuickAccessView: View {
    let model: QuickAccessModel
    let controller: QuickAccessController
    @Setting(PreferenceKey.quickAccessPosition) private var position: QuickAccessPosition

    private var edge: Edge { position == .right ? .trailing : .leading }

    private var transition: AnyTransition {
        guard !QuickAccessMotion.reduced else {
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
        .environment(\.colorScheme, .light)
    }
}

private struct QuickAccessCardView: View {
    let card: QuickAccessCard
    let controller: QuickAccessController
    @State private var hovering = false

    var body: some View {
        ZStack {
            Image(nsImage: card.thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: QuickAccessCard.width, height: card.height)
                .accessibilityLabel(Text("\(card.isVideo ? "Recording" : "Screenshot") \(card.fileURL.lastPathComponent)"))
            if hovering {
                hoverActions
                    .transition(.opacity)
            } else if card.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Brutal.ink)
                    .frame(width: 34, height: 34)
                    .brutalCircle(Brutal.yellow, shadow: 2)
            }
        }
        .frame(width: QuickAccessCard.width, height: card.height)
        .background(Color.black)
        .inkBorder(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular), width: 2)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = inside
            }
            controller.setHovering(inside, card: card.id)
        }
        .onDrag { NSItemProvider(contentsOf: card.styledURL ?? card.fileURL) ?? NSItemProvider() }
        .contextMenu { menu }
    }

    /// The hover buttons' actions again, plus Copy Path, which has no button: the card stays as plain as it is.
    @ViewBuilder
    private var menu: some View {
        Button("Copy") { controller.copy(card) }
        Button("Copy Path") { controller.copyPath(card) }
        Button("Save As…") { controller.saveAs(card) }
        Divider()
        Button(card.isVideo ? "Edit Video" : "Annotate") { controller.annotate(card) }
        if card.isVideo {
            Button("Export GIF") { controller.exportGIF(card) }
        }
        Button("Show in Finder") { controller.showInFinder(card) }
    }

    private var hoverActions: some View {
        ZStack {
            // Dimmed rather than blurred, so the screenshot still shows behind the buttons.
            Color.black.opacity(0.35)
            VStack(spacing: 9) {
                Button("Copy") { controller.copy(card) }
                    .buttonStyle(BrutalButtonStyle(color: Brutal.yellow, compact: true))
                Button("Save As…") { controller.saveAs(card) }
                    .buttonStyle(BrutalButtonStyle(compact: true))
            }
            VStack {
                HStack {
                    CornerButton(symbol: "xmark", help: "Close") { controller.remove(card.id) }
                    Spacer()
                    if card.isVideo {
                        CornerButton(symbol: "scissors", help: "Edit Video") { controller.annotate(card) }
                        CornerButton(symbol: "photo.stack", help: "Export GIF") { controller.exportGIF(card) }
                    } else {
                        CornerButton(symbol: "pencil", help: "Annotate") { controller.annotate(card) }
                    }
                }
                Spacer()
                HStack {
                    Spacer()
                    CornerButton(symbol: "folder", help: "Show in Finder") { controller.showInFinder(card) }
                }
            }
            .padding(10)
        }
    }
}

struct CornerButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(CornerButtonStyle())
        .brutalTip(help)
        .accessibilityLabel(Text(help))
    }
}

private struct CornerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(Brutal.ink)
            .frame(width: 24, height: 24)
            .brutalSurface(Color.white, radius: Brutal.Radius.chip, shadow: pressed ? 0 : 2)
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
    }
}
