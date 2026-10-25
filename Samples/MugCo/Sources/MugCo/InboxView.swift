import SwiftUI

struct InboxView: View {
    @State private var selectedID: String? = SampleData.conversations.first?.id
    @State private var reply = ""

    private var selected: Conversation {
        SampleData.conversations.first { $0.id == selectedID } ?? SampleData.conversations[0]
    }

    var body: some View {
        HStack(spacing: 0) {
            List(SampleData.conversations, selection: $selectedID) { conversation in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(conversation.name).fontWeight(.semibold)
                        Spacer()
                        Text(conversation.when).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(conversation.preview).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 4)
            }
            .frame(width: 260)

            Divider()
            ThreadView(conversation: selected, reply: $reply)
            Divider()
            OrderView(order: selected.order)
                .frame(width: 280)
        }
    }
}

private struct ThreadView: View {
    let conversation: Conversation
    @Binding var reply: String

    var body: some View {
        VStack(spacing: 0) {
            Text(conversation.name).font(.headline).padding()
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(conversation.messages) { message in
                        HStack {
                            if !message.fromCustomer { Spacer(minLength: 60) }
                            Text(message.text)
                                .padding(10)
                                .background(message.fromCustomer ? Color.secondary.opacity(0.18) : Color.accentColor)
                                .foregroundStyle(message.fromCustomer ? Color.primary : Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .circular))
                            if message.fromCustomer { Spacer(minLength: 60) }
                        }
                    }
                }
                .padding()
            }
            Divider()
            HStack {
                TextField("Reply to \(conversation.name)", text: $reply)
                Button("Send") { reply = "" }
                    .buttonStyle(.borderedProminent)
                    .disabled(reply.isEmpty)
            }
            .padding()
        }
    }
}

private struct OrderView: View {
    let order: Order

    var body: some View {
        Form {
            Section("Order") {
                LabeledContent("Number", value: order.number)
                LabeledContent("Item", value: order.item)
            }
            Section("Customer") {
                LabeledContent("Email", value: order.email)
                LabeledContent("Card", value: order.card)
            }
            Section("Account") {
                LabeledContent("Balance") {
                    Text(order.balance).foregroundStyle(order.balance.hasPrefix("-") ? .red : .primary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
