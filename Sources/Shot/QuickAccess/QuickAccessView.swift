import ShotCore
import SwiftUI

struct QuickAccessView: View {
    let model: QuickAccessModel
    let controller: QuickAccessController
    @AppStorage(PreferenceKey.quickAccessPosition) private var position = QuickAccessPosition.left.rawValue

    var body: some View {
        VStack(spacing: QuickAccessController.spacing) {
            ForEach(model.cards) { card in
                QuickAccessCardView(card: card, controller: controller)
                    .transition(.move(edge: position == QuickAccessPosition.right.rawValue ? .trailing : .leading).combined(with: .opacity))
            }
        }
        .padding(QuickAccessController.padding)
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
        .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular))
        .brutalSurface(Color.clear)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = inside
            }
            controller.setHovering(inside, card: card.id)
        }
        .onDrag { NSItemProvider(contentsOf: card.fileURL) ?? NSItemProvider() }
    }

    private var hoverActions: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.white.opacity(0.25)
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
                        CornerButton(symbol: "scissors", help: "Edit") { controller.annotate(card) }
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

private struct CornerButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(CornerButtonStyle())
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

private struct CornerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(Brutal.ink)
            .frame(width: 24, height: 24)
            .brutalSurface(Color.white, radius: 6, shadow: pressed ? 0 : 2)
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
    }
}
