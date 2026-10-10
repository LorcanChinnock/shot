import SwiftUI

// Fixed, made-up data with placeholder names. No clocks and no randomness, so a re-shoot matches the last one.
// The one email address uses the reserved example.com domain.

let brand = Color(red: 0.13, green: 0.55, blue: 0.45)

struct Person {
    let name: String
    let initials: String
    let colour: Color
}

enum People {
    static let jane = Person(name: "Jane Doe", initials: "JD", colour: .orange)
    static let alex = Person(name: "Alex Smith", initials: "AS", colour: .pink)
    static let sam = Person(name: "Sam Taylor", initials: "ST", colour: .blue)
    static let chris = Person(name: "Chris Lee", initials: "CL", colour: .purple)
    static let agents = [alex, sam, chris]
}

struct Avatar: View {
    let person: Person
    var size: CGFloat = 28

    var body: some View {
        Text(person.initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(person.colour.gradient, in: Circle())
    }
}

struct Tag: View {
    let text: String
    let colour: Color

    init(_ text: String, _ colour: Color) {
        self.text = text
        self.colour = colour
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(colour)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(colour.opacity(0.14), in: Capsule())
    }
}

/// The left column every main scene shares, with the scene's own item selected.
struct Sidebar: View {
    enum Item: String, CaseIterable {
        case inbox = "Inbox", tickets = "Tickets", customers = "Customers", reports = "Reports", settings = "Settings"

        var symbol: String {
            switch self {
            case .inbox: "tray"
            case .tickets: "ticket"
            case .customers: "person.2"
            case .reports: "chart.bar"
            case .settings: "gearshape"
            }
        }
    }

    let selected: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "bag.fill")
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(brand.gradient, in: RoundedRectangle(cornerRadius: 6))
                Text("Acme").font(.system(size: 15, weight: .bold))
            }
            .padding(.top, 40)
            .padding(.bottom, 18)
            .padding(.horizontal, 8)

            ForEach(Item.allCases, id: \.self) { item in
                HStack(spacing: 9) {
                    Image(systemName: item.symbol).frame(width: 18)
                    Text(item.rawValue)
                    Spacer()
                    if item == .inbox { Text("12").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
                }
                .font(.system(size: 13, weight: item == selected ? .semibold : .regular))
                .foregroundStyle(item == selected ? brand : .primary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(item == selected ? brand.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }

            Spacer()
            HStack(spacing: 8) {
                Avatar(person: People.alex, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Alex Smith").font(.system(size: 12, weight: .semibold))
                    Text("Online").font(.system(size: 11)).foregroundStyle(.green)
                }
            }
            .padding(8)
        }
        .padding(10)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(.quinary)
    }
}

/// A short confirmation at the bottom of a scene, like the real app would show after an action.
struct Toast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Shows `text` as a toast for two seconds whenever it's set.
    func toast(_ text: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let message = text.wrappedValue {
                Toast(text: message)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { text.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: text.wrappedValue)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}
