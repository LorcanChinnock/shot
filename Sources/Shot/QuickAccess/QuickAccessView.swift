import SwiftUI

struct QuickAccessView: View {
    let model: QuickAccessModel
    let controller: QuickAccessController

    var body: some View {
        VStack(spacing: QuickAccessController.spacing) {
            ForEach(model.cards) { card in
                QuickAccessCardView(card: card, controller: controller)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(QuickAccessController.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct QuickAccessCardView: View {
    let card: QuickAccessCard
    let controller: QuickAccessController
    @State private var hovering = false

    private static let radius: CGFloat = 10

    var body: some View {
        ZStack {
            Image(nsImage: card.thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: QuickAccessCard.width, height: card.height)
                .clipped()
            if hovering {
                hoverActions
                    .transition(.opacity)
            } else if card.isVideo {
                videoBadge
            }
        }
        .frame(width: QuickAccessCard.width, height: card.height)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
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
            Color.black.opacity(0.55)
            VStack(spacing: 8) {
                PillButton(title: "Copy") { controller.copy(card) }
                PillButton(title: "Save As…") { controller.saveAs(card) }
            }
            VStack {
                HStack {
                    CornerButton(symbol: "xmark", help: "Close") { controller.remove(card.id) }
                    Spacer()
                    if card.isVideo {
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
            .padding(7)
        }
    }

    private var videoBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Color.black.opacity(0.55), in: Circle())
    }
}

private struct PillButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.85))
                .frame(width: 104, height: 26)
                .background(Color.white.opacity(hovering ? 1 : 0.88), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct CornerButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(hovering ? 0.35 : 0.2), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
