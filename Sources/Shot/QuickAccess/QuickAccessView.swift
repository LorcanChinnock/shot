import SwiftUI

struct QuickAccessView: View {
    let model: QuickAccessModel
    let controller: QuickAccessController

    var body: some View {
        VStack(spacing: QuickAccessController.spacing) {
            ForEach(model.cards) { card in
                QuickAccessCardView(card: card, controller: controller)
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

    var body: some View {
        Image(nsImage: card.thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: QuickAccessCard.width, height: card.height)
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if hovering {
                    actions
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .onHover { inside in
                hovering = inside
                controller.setHovering(inside, card: card.id)
            }
            .onDrag { NSItemProvider(contentsOf: card.fileURL) ?? NSItemProvider() }
    }

    private var actions: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45))
            VStack(spacing: 6) {
                Spacer()
                HStack(spacing: 6) {
                    button("Copy", "doc.on.doc") { controller.copy(card) }
                    button("Save As…", "square.and.arrow.down") { controller.saveAs(card) }
                }
                HStack(spacing: 6) {
                    if card.isVideo {
                        button("GIF", "photo.stack") { controller.exportGIF(card) }
                    } else {
                        button("Annotate", "pencil.tip.crop.circle") { controller.annotate(card) }
                    }
                    button("Show in Finder", "folder") { controller.showInFinder(card) }
                }
                Spacer()
            }
            Button {
                controller.remove(card.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("Close")
        }
    }

    private func button(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
