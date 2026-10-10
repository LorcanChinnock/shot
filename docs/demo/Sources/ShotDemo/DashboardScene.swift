import Charts
import SwiftUI

/// A revenue report whose chart grows in and whose order list fills in, so a recording has something moving.
struct DashboardScene: View {
    @State private var shown = false
    @State private var rows = 0

    private let revenue: [Double] = [920, 1140, 1010, 1380, 1250, 1490, 1720, 1310, 1180, 1460, 1630, 1550, 1810, 2040]
    private let orders: [(id: String, customer: String, amount: String, status: (String, Color))] = [
        ("#A-20931", "Jane Doe", "$134.50", ("Paid", .green)),
        ("#A-20930", "John Smith", "$58.00", ("Paid", .green)),
        ("#A-20929", "Mary Jones", "$22.90", ("Refunded", .orange)),
        ("#A-20928", "Tom Brown", "$310.00", ("Paid", .green)),
        ("#A-20927", "Emma Wilson", "$76.40", ("Pending", .blue)),
    ]

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selected: .reports)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Revenue").font(.system(size: 20, weight: .bold))
                    Text("Last 14 days").foregroundStyle(.secondary)
                    Spacer()
                    Button("Export CSV", systemImage: "square.and.arrow.down") {}
                }
                .padding(.top, 34)

                HStack(spacing: 12) {
                    tile("Revenue", "$19,890", "+12%", .green)
                    tile("Orders", "412", "+8%", .green)
                    tile("Conversion", "3.4%", "−0.2 pt", .red)
                    tile("Refunds", "6", "−3", .green)
                }

                Card {
                    Chart(revenue.indices, id: \.self) { day in
                        BarMark(x: .value("Day", day + 1), y: .value("Revenue", shown ? revenue[day] : 0), width: 22)
                            .foregroundStyle(day == revenue.count - 1 ? brand.gradient : brand.opacity(0.45).gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .chartXScale(domain: 0.4...14.6)
                    .chartYScale(domain: 0...2200)
                    .chartXAxis { AxisMarks(values: [1, 7, 14]) { value in AxisValueLabel("\(value.as(Int.self) ?? 0)") } }
                    .chartYAxis { AxisMarks(position: .leading, values: [0, 1000, 2000]) { AxisGridLine(); AxisValueLabel() } }
                    .frame(height: 170)
                }

                Card {
                    VStack(spacing: 8) {
                        ForEach(orders.indices.prefix(rows), id: \.self) { index in
                            let order = orders[index]
                            HStack {
                                Text(order.id).font(.system(size: 12, design: .monospaced)).frame(width: 80, alignment: .leading)
                                Text(order.customer).font(.system(size: 13))
                                Spacer()
                                Tag(order.status.0, order.status.1)
                                Text(order.amount).font(.system(size: 13, weight: .medium)).monospacedDigit().frame(width: 70, alignment: .trailing)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 150, alignment: .top)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(duration: 0.9, bounce: 0.2)) { shown = true }
            for _ in orders {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(.spring(duration: 0.4)) { rows += 1 }
            }
        }
    }

    private func tile(_ label: String, _ value: String, _ change: String, _ colour: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 20, weight: .bold)).monospacedDigit()
                Text(change).font(.system(size: 11, weight: .semibold)).foregroundStyle(colour)
            }
        }
    }
}
