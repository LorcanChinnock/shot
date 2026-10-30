import SwiftUI

/// A help centre article much taller than the window, for the scrolling capture's guide media: a toolbar that stays
/// at the top, a sidebar that stays at the left, a floating button over the text, and enough sections to scroll
/// through. Everything is fixed, so a re-shoot lines up with the last one.
struct ArticleScene: View {
    static let sections: [(title: String, paragraphs: [String])] = [
        ("Refunds and returns", [
            "A customer can return any mug within 30 days of delivery, whatever the reason. Open the order, choose Start a return, and the customer gets a prepaid label by email the same day.",
            "Refunds go back to the card the order was paid with. Once the mug reaches the warehouse, the refund takes three to five working days to show on the customer's statement.",
            "A mug that arrived damaged doesn't need to come back. Ask for a photo, attach it to the ticket, and refund the order from the ticket's Order panel.",
        ]),
        ("Changing an address", [
            "An order can be sent to a different address until it's packed, which is usually within two hours of the order coming in. After that, ask the courier to hold it at the nearest depot instead.",
            "Change the address from the order's Delivery panel. The customer gets a confirmation email with the new address, and the label is reprinted before the parcel leaves.",
        ]),
        ("Discount codes", [
            "A code applies to the mugs in the basket, never to delivery. If a customer says a code isn't working, check its end date and whether it's limited to one use per customer.",
            "Codes are case-insensitive. A code that has reached its limit shows as Expired in the Discounts list, with the date it ran out.",
            "To make a one-off code for a customer, open Discounts, choose New code, and set it to one use. It expires after seven days unless you pick another date.",
        ]),
        ("Gift cards", [
            "A gift card's balance is on the card's own page, with every order it has paid for. If the balance looks wrong, compare it with the orders listed there before you adjust it.",
            "A gift card never expires, and it can be used across several orders. The remaining balance stays on the card.",
        ]),
        ("Where is my order?", [
            "Every order has a tracking link in its Delivery panel. If the courier hasn't scanned the parcel for three days, open a claim with them from the same panel, and let the customer know.",
            "Orders placed before 2 pm leave the same day. Weekend orders leave on Monday.",
            "If a parcel is marked delivered but the customer hasn't got it, ask them to check with neighbours and the building's post room first. Most turn up within a day.",
        ]),
        ("Personalised mugs", [
            "A personalised mug can't be returned unless it's faulty or the text is wrong. Check the preview the customer approved before you agree to a reprint.",
            "Reprints go to the front of the queue and leave within a day. The customer keeps the first mug.",
        ]),
        ("Wholesale orders", [
            "Orders of 50 mugs or more go to the wholesale team. Assign the ticket to them and let the customer know someone will reply within a working day.",
            "Wholesale customers get an invoice rather than paying at checkout. Their orders show an Invoice tag in the list.",
        ]),
        ("Escalating a ticket", [
            "Escalate a ticket when a customer asks for a manager, when an order has been lost twice, or when a refund is over £200. Add a note that says what you've already tried.",
            "Escalated tickets are answered within four hours during the day. The customer gets an email saying their ticket has been passed on.",
        ]),
    ]

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selected: .settings)
            Divider()
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            VStack(alignment: .leading, spacing: 22) {
                                Text("Help centre").font(.system(size: 26, weight: .bold)).padding(.top, 18)
                                Text("What to tell customers, and what to do in the app, for the questions that come up most. Search the inbox for the customer's order number first; most answers are in the order.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                ForEach(Self.sections.indices, id: \.self) { index in
                                    let section = Self.sections[index]
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(section.title).font(.system(size: 18, weight: .semibold)).padding(.top, 10)
                                        ForEach(section.paragraphs.indices, id: \.self) { paragraph in
                                            Text(section.paragraphs[paragraph]).font(.system(size: 14)).lineSpacing(3)
                                        }
                                    }
                                }
                                Text("Last updated 3 weeks ago by Alex Smith").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.vertical, 24)
                            }
                            .frame(maxWidth: 560, alignment: .leading)
                            .padding(.horizontal, 36)
                        } header: {
                            toolbar
                        }
                    }
                }
                Button {} label: {
                    Label("Was this helpful?", systemImage: "hand.thumbsup")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .tint(brand)
                .padding(20)
            }
        }
    }

    /// Stays at the top of the article while it scrolls.
    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Support guide").font(.system(size: 13, weight: .semibold))
            Text("›").foregroundStyle(.tertiary)
            Text("Orders and refunds").font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Tag("8 articles", brand)
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }
}
