import Foundation

// Everything here is made up. The email address uses example.com and the card number is a well-known test number,
// so a capture of the app is safe to publish.

struct Message: Identifiable {
    let id = UUID()
    let fromCustomer: Bool
    let text: String
}

struct Conversation: Identifiable {
    let id: String
    let name: String
    let preview: String
    let when: String
    let order: Order
    let messages: [Message]
}

struct Order: Equatable {
    let number: String
    let item: String
    let email: String
    let card: String
    let balance: String
}

enum SampleData {
    static let conversations: [Conversation] = [
        Conversation(
            id: "james", name: "James Hart", preview: "Mug arrived chipped", when: "10:42",
            order: Order(
                number: "#A-20877", item: "Stoneware mug, blue", email: "james.hart@example.com",
                card: "4242 4242 4242 4242", balance: "-£4.20"
            ),
            messages: [
                Message(fromCustomer: true, text: "Hi, my mug arrived chipped on the rim."),
                Message(fromCustomer: false, text: "Sorry about that, James. Could you send a photo?"),
                Message(fromCustomer: true, text: "Sure. Also my balance is wrong. It says I owe you money."),
            ]
        ),
        Conversation(
            id: "priya", name: "Priya Nair", preview: "Can I change my address?", when: "09:15",
            order: Order(
                number: "#A-20871", item: "Tea set, white", email: "priya.nair@example.com",
                card: "4000 0566 5566 5556", balance: "£0.00"
            ),
            messages: [
                Message(fromCustomer: true, text: "Can I change the delivery address before it ships?"),
                Message(fromCustomer: false, text: "Yes, send me the new one and I'll update it."),
            ]
        ),
        Conversation(
            id: "tom", name: "Tom Wilson", preview: "Where is order #A-20877?", when: "Yesterday",
            order: Order(
                number: "#A-20860", item: "Milk jug, green", email: "tom.wilson@example.com",
                card: "5555 5555 5555 4444", balance: "£0.00"
            ),
            messages: [
                Message(fromCustomer: true, text: "Where is my order? It was due on Friday."),
                Message(fromCustomer: false, text: "It's with the courier and should arrive tomorrow."),
            ]
        ),
        Conversation(
            id: "mei", name: "Mei Tanaka", preview: "Thanks, that fixed it", when: "Yesterday",
            order: Order(
                number: "#A-20852", item: "Espresso cups, set of 4", email: "mei.tanaka@example.com",
                card: "3782 822463 10005", balance: "£0.00"
            ),
            messages: [
                Message(fromCustomer: true, text: "Thanks, that fixed it."),
            ]
        ),
    ]
}
