import SwiftUI

/// A support ticket: something to point arrows at, plus an email and phone number to redact.
struct TicketScene: View {
    @State private var assignee: Person?
    @State private var choosing = false
    @State private var toast: String?

    static let tickets: [(subject: String, customer: String, time: String, tag: (String, Color))] = [
        ("Discount code isn't applied at checkout", "Jane Doe", "09:42", ("High", .red)),
        ("Can I change my delivery address?", "John Smith", "09:17", ("Orders", .blue)),
        ("Refund for a damaged mug", "Mary Jones", "08:55", ("Refunds", .orange)),
        ("Gift card balance is wrong", "Tom Brown", "Yesterday", ("Billing", .purple)),
        ("Where is order #A-20877?", "Emma Wilson", "Yesterday", ("Orders", .blue)),
    ]

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selected: .tickets)
            Divider()
            list
            Divider()
            detail
        }
        .toast($toast)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("Search tickets").foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(8)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 12)
            .padding(.top, 40)
            .padding(.bottom, 10)

            ForEach(Self.tickets.indices, id: \.self) { index in
                let ticket = Self.tickets[index]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(ticket.customer).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(clock(ticket.time)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(ticket.subject).font(.system(size: 12)).lineLimit(1)
                    Tag(ticket.tag.0, ticket.tag.1)
                }
                .padding(10)
                .background(index == 0 ? brand.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 6)
            }
            Spacer()
        }
        .frame(width: 250)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("#4821").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    choosing = true
                } label: {
                    if let assignee {
                        Label(assignee.name, systemImage: "person.crop.circle.badge.checkmark")
                    } else {
                        Label("Assign", systemImage: "person.crop.circle.badge.plus")
                    }
                }
                .popover(isPresented: $choosing, arrowEdge: .bottom) { picker }
                Button("Reply") { toast = "Reply sent to Jane" }
                    .buttonStyle(.borderedProminent)
                    .tint(brand)
            }
            .padding(.top, 34)

            Text("Discount code isn't applied at checkout").font(.system(size: 20, weight: .bold))
            HStack(spacing: 6) {
                Tag("High priority", .red)
                Tag("Checkout", .blue)
                Tag("Promotions", .purple)
            }

            Card {
                HStack(alignment: .top, spacing: 10) {
                    Avatar(person: People.jane, size: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Jane Doe").font(.system(size: 13, weight: .semibold))
                            Text(clock("09:42")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text("jane.doe@example.com").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("I entered SPRING20 and it says the code is valid, but the total doesn't change. I tried twice on my phone and once on my laptop.")
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Card {
                VStack(spacing: 7) {
                    HStack {
                        Text("Order #A-20931").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Placed today").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Divider()
                    line("Trail runners, size 9", "$128.00")
                    line("Shipping", "$6.50")
                    line("Discount  SPRING20", "−$0.00", highlight: true)
                    Divider()
                    line("Total", "$134.50", bold: true)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "paperclip").foregroundStyle(.secondary)
                Text("Reply to Jane…").foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "paperplane.fill").foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.secondary.opacity(0.35)))
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    private func line(_ label: String, _ amount: String, highlight: Bool = false, bold: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(amount).monospacedDigit()
        }
        .font(.system(size: 13, weight: bold ? .semibold : .regular))
        .foregroundStyle(highlight ? Color.red : Color.primary)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Assign to").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
            ForEach(People.agents, id: \.name) { person in
                Button {
                    assignee = person
                    choosing = false
                    toast = "Assigned to \(person.name)"
                } label: {
                    HStack {
                        Avatar(person: person, size: 22)
                        Text(person.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(5)
            }
        }
        .padding(10)
        .frame(width: 200)
    }
}
