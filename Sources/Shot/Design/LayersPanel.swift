import SwiftUI

struct LayerRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let symbol: String
    let isHidden: Bool
    let isLocked: Bool
}

/// The stack of layers, frontmost first, with the base image locked at the bottom. The photo editor lists its annotations
/// here and the video editor its overlay tracks.
struct LayersPanel: View {
    static let width: CGFloat = 230

    let rows: [LayerRow]
    let baseName: String
    let baseSymbol: String
    @Binding var selection: Set<UUID>
    let onMove: (IndexSet, Int) -> Void
    let onHide: (Set<UUID>, Bool) -> Void
    let onLock: (Set<UUID>, Bool) -> Void
    let onDuplicate: ((Set<UUID>) -> Void)?
    let onDelete: (Set<UUID>) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("LAYERS")
                .font(.system(size: 11, weight: .black))
                .tracking(1.2)
                .foregroundStyle(Brutal.ink.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Divider().overlay(Brutal.ink.opacity(0.25))
            List(selection: $selection) {
                ForEach(rows) { row in
                    LayerRowView(row: row, onHide: { onHide([row.id], !row.isHidden) }, onLock: { onLock([row.id], !row.isLocked) })
                        .tag(row.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                }
                .onMove(perform: onMove)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: UUID.self) { ids in
                menu(for: ids)
            }
            .overlay {
                if rows.isEmpty {
                    Text("Nothing drawn yet")
                        .font(Brutal.caption)
                        .foregroundStyle(Brutal.ink.opacity(0.55))
                        .allowsHitTesting(false)
                }
            }
            Divider().overlay(Brutal.ink.opacity(0.25))
            HStack(spacing: 8) {
                Image(systemName: baseSymbol).frame(width: 18)
                Text(baseName).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Brutal.ink.opacity(0.45))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Brutal.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: Self.width)
        .clipShape(RoundedRectangle(cornerRadius: Brutal.radius, style: .circular))
        .glassCard()
    }

    @ViewBuilder
    private func menu(for ids: Set<UUID>) -> some View {
        let chosen = rows.filter { ids.contains($0.id) }
        if !chosen.isEmpty {
            if let onDuplicate {
                Button("Duplicate") { onDuplicate(ids) }
            }
            Button("Delete") { onDelete(ids) }
            Divider()
            let lock = !chosen.allSatisfy(\.isLocked)
            Button(lock ? "Lock" : "Unlock") { onLock(ids, lock) }
            let hide = !chosen.allSatisfy(\.isHidden)
            Button(hide ? "Hide" : "Show") { onHide(ids, hide) }
        }
    }
}

private struct LayerRowView: View {
    let row: LayerRow
    let onHide: () -> Void
    let onLock: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 18)
            Text(row.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            toggle(row.isLocked ? "lock.fill" : "lock.open", on: row.isLocked, label: row.isLocked ? "Unlock" : "Lock", action: onLock)
            toggle(row.isHidden ? "eye.slash" : "eye", on: row.isHidden, label: row.isHidden ? "Show" : "Hide", action: onHide)
        }
        .foregroundStyle(Brutal.ink)
        .opacity(row.isHidden ? 0.45 : 1)
        .contentShape(Rectangle())
    }

    /// Shown dimmed until set or hovered, so an unlocked, visible row isn't cluttered.
    private func toggle(_ symbol: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 20, height: 20)
                .opacity(on ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .brutalTip(label)
    }
}
