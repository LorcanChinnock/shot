import AppKit
import SwiftUI

/// A team chat to paste a screenshot into: click the composer, ⌘V, then Return.
struct ChatScene: View {
    private struct Message: Identifiable {
        let id: Int
        let person: Person
        let time: String
        var text = ""
        var image: NSImage?
    }

    @State private var messages = [
        Message(id: 0, person: People.chris, time: clock("09:51"), text: "Anyone else seeing SPRING20 fail at checkout?"),
        Message(id: 1, person: People.sam, time: clock("09:53"), text: "Got a screenshot? It works on staging."),
    ]
    @State private var draft = ""
    @State private var attachment: NSImage?
    @FocusState private var composing: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("# checkout").font(.system(size: 15, weight: .bold))
                Text("Bugs and fixes for the checkout flow").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 12)
            Divider()

            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(messages) { message in
                            row(message).id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) {
                    withAnimation { scroller.scrollTo(messages.count - 1, anchor: .bottom) }
                }
            }

            composer
        }
    }

    private func row(_ message: Message) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(person: message.person, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(message.person.name).font(.system(size: 13, weight: .semibold))
                    Text(message.time).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if !message.text.isEmpty { Text(message.text).font(.system(size: 13)) }
                if let image = message.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 290, maxHeight: 220, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                }
            }
        }
    }

    // Not a TextField: a text field's editor swallows image pastes, so this takes keys and ⌘V itself.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attachment {
                Image(nsImage: attachment)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 120, maxHeight: 70, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Text(draft.isEmpty ? "Message #checkout" : draft)
                    .foregroundStyle(draft.isEmpty ? .tertiary : .primary)
                Spacer()
                Image(systemName: "paperplane.fill").foregroundStyle(canSend ? brand : .secondary)
            }
        }
        .font(.system(size: 13))
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(composing ? brand : Color.secondary.opacity(0.35), lineWidth: composing ? 2 : 1))
        .padding(12)
        .focusable()
        .focusEffectDisabled()
        .focused($composing)
        .onTapGesture { composing = true }
        .onPasteCommand(of: [.image, .png, .tiff]) { _ in
            if let image = NSImage(pasteboard: .general) { attachment = image }
        }
        .onKeyPress(.return) {
            send()
            return .handled
        }
        .onKeyPress(.delete) {
            if !draft.isEmpty { draft.removeLast() } else { attachment = nil }
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.subtracting(.shift).isEmpty, let character = press.characters.first,
                  !character.isNewline, character.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else { return .ignored }
            draft += press.characters
            return .handled
        }
    }

    private var canSend: Bool { !draft.isEmpty || attachment != nil }

    private func send() {
        guard canSend else { return }
        withAnimation(.spring(duration: 0.35)) {
            messages.append(Message(id: messages.count, person: People.alex, time: clock("09:54"), text: draft, image: attachment))
        }
        draft = ""
        attachment = nil
    }
}
