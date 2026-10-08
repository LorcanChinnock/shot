import AppKit
import ShotCore
import SwiftUI

struct LayerRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let symbol: String
    let isHidden: Bool
    let isLocked: Bool
}

/// The photo editor's annotations as a stack of layers, frontmost first, with the image locked at the bottom.
struct LayersPanel: View {
    static let width: CGFloat = 230
    nonisolated static let rowHeight: CGFloat = 30
    private static let space = "layers"

    let rows: [LayerRow]
    @Binding var selection: Set<UUID>
    /// The rows at the offsets moved to before the row at the destination, as `List`'s `onMove` passes them.
    let onMove: (IndexSet, Int) -> Void
    let onHide: (Set<UUID>, Bool) -> Void
    let onLock: (Set<UUID>, Bool) -> Void
    let onDuplicate: (Set<UUID>) -> Void
    let onDelete: (Set<UUID>) -> Void

    @FocusState private var isFocused: Bool
    @State private var drag: RowDrag?
    /// Set by Escape, so the rest of that drag does nothing.
    @State private var dragCancelled = false
    @State private var escapeMonitor: Any?
    @State private var listSize: CGSize = .zero
    /// Where a ⇧-click range starts.
    @State private var anchor: UUID?

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
            ScrollView {
                ZStack(alignment: .top) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(drag.map { $0.rest.count + 1 } ?? rows.count) * Self.rowHeight, alignment: .top)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .scrollDisabled(drag != nil)
            .coordinateSpace(.named(Self.space))
            .onGeometryChange(for: CGSize.self, of: \.size) { listSize = $0 }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onDeleteCommand {
                onDelete(selection)
            }
            .onMoveCommand(perform: moveSelection)
            .overlay {
                if rows.isEmpty {
                    EmptyLayers().allowsHitTesting(false)
                }
            }
            Divider().overlay(Brutal.ink.opacity(0.25))
            HStack(spacing: 8) {
                Image(systemName: "photo").frame(width: 18)
                Text("Image")
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
        .onDisappear(perform: stopWatchingEscape)
    }

    private func rowView(_ row: LayerRow) -> some View {
        let lifted = drag?.id == row.id
        let carried = drag.map { $0.moving.contains(row.id) && !lifted } ?? false
        return LayerRowView(
            row: row,
            isSelected: selection.contains(row.id),
            isFocused: isFocused,
            isLifted: lifted,
            grip: grip(for: row),
            onHide: { onHide([row.id], !row.isHidden) },
            onLock: { onLock([row.id], !row.isLocked) },
            onDelete: { onDelete([row.id]) }
        )
        .frame(height: Self.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { click(row.id) }
        .contextMenu { menu(for: selection.contains(row.id) ? selection : [row.id]) }
        // Carried rows ride under the lifted one, which fades while a drop would cancel.
        .opacity(carried ? 0 : lifted && drag?.isOutside == true ? 0.5 : 1)
        // The lifted row follows the pointer; the others glide to open the gap.
        .offset(y: y(of: row.id))
        .animation(lifted ? nil : .snappy(duration: 0.2), value: drag?.gap)
        .zIndex(lifted ? 1 : 0)
    }

    @ViewBuilder
    private func menu(for ids: Set<UUID>) -> some View {
        let chosen = rows.filter { ids.contains($0.id) }
        if !chosen.isEmpty {
            Button("Duplicate") { onDuplicate(ids) }
            Button("Delete") { onDelete(ids) }
            Divider()
            let lock = !chosen.allSatisfy(\.isLocked)
            Button(lock ? "Lock" : "Unlock") { onLock(ids, lock) }
            let hide = !chosen.allSatisfy(\.isHidden)
            Button(hide ? "Hide" : "Show") { onHide(ids, hide) }
        }
    }

    // MARK: Selection

    /// A click selects the row, ⌘-click adds or removes it, and ⇧-click selects the rows from the last one clicked.
    private func click(_ id: UUID) {
        isFocused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            selection.formSymmetricDifference([id])
            anchor = id
        } else if flags.contains(.shift), let anchor, let from = rows.firstIndex(where: { $0.id == anchor }), let to = rows.firstIndex(where: { $0.id == id }) {
            selection = Set(rows[min(from, to)...max(from, to)].map(\.id))
        } else {
            selection = [id]
            anchor = id
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let step = switch direction {
        case .up: -1
        case .down: 1
        default: 0
        }
        guard step != 0, !rows.isEmpty else {
            return
        }
        let current = rows.firstIndex { selection.contains($0.id) }
        let next = current.map { min(max($0 + step, 0), rows.count - 1) } ?? (step > 0 ? 0 : rows.count - 1)
        selection = [rows[next].id]
        anchor = rows[next].id
    }

    // MARK: Dragging

    /// Where a row sits: its place in the list, or while a drag is under way, its place among the rows that stay with a
    /// gap where the dragged ones will land, or for the row being dragged, under the pointer.
    private func y(of id: UUID) -> CGFloat {
        guard let drag else {
            return CGFloat(rows.firstIndex { $0.id == id } ?? 0) * Self.rowHeight
        }
        if drag.moving.contains(id) {
            return (CGFloat(drag.start) * Self.rowHeight + drag.translation)
        }
        let index = drag.rest.firstIndex(of: id) ?? 0
        return CGFloat(index < drag.gap ? index : index + 1) * Self.rowHeight
    }

    private func grip(for row: LayerRow) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !dragCancelled else {
                    return
                }
                if drag == nil {
                    withAnimation(.snappy(duration: 0.2)) {
                        drag = RowDrag(id: row.id, moving: movingIDs(grabbing: row.id), rows: rows)
                    }
                    watchEscape()
                }
                drag?.isOutside = !CGRect(origin: .zero, size: listSize).contains(value.location)
                drag?.translation = value.translation.height
            }
            .onEnded { _ in
                defer { dragCancelled = false }
                guard !dragCancelled, let drag else {
                    return
                }
                stopWatchingEscape()
                withAnimation(.snappy(duration: 0.25)) {
                    if !drag.isOutside, let destination = drag.destination(in: rows) {
                        onMove(IndexSet(rows.indices.filter { drag.moving.contains(rows[$0].id) }), destination)
                    }
                    self.drag = nil
                }
            }
    }

    /// The rows a drag moves: the selection when it includes the grabbed row, else just that row.
    private func movingIDs(grabbing id: UUID) -> Set<UUID> {
        selection.contains(id) ? selection.intersection(rows.map(\.id)) : [id]
    }

    private func watchEscape() {
        guard escapeMonitor == nil else {
            return
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else {
                return event
            }
            MainActor.assumeIsolated { cancelDrag() }
            return nil
        }
    }

    private func stopWatchingEscape() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
    }

    private func cancelDrag() {
        stopWatchingEscape()
        guard drag != nil else {
            return
        }
        dragCancelled = true
        withAnimation(.snappy(duration: 0.25)) {
            drag = nil
        }
    }
}

/// A scribble badge, tilted as if stuck on by hand, over what to do first.
private struct EmptyLayers: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(Brutal.ink)
                .frame(width: 54, height: 54)
                .brutalCircle(Brutal.yellow, shadow: 3)
                .rotationEffect(.degrees(-8))
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Nothing drawn yet")
                    .font(Brutal.label)
                    .foregroundStyle(Brutal.ink.opacity(0.8))
                Text("Pick a tool and draw on the image")
                    .font(Brutal.caption)
                    .foregroundStyle(Brutal.ink.opacity(0.55))
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
    }
}

/// A drag of one row, carrying the others in `moving` with it.
private struct RowDrag {
    let id: UUID
    let moving: Set<UUID>
    /// The rows that stay, in order.
    let rest: [UUID]
    /// The dragged row's place among `rest`, where it started.
    let start: Int
    var translation: CGFloat = 0
    var isOutside = false

    init(id: UUID, moving: Set<UUID>, rows: [LayerRow]) {
        self.id = id
        self.moving = moving
        rest = rows.map(\.id).filter { !moving.contains($0) }
        let index = rows.firstIndex { $0.id == id } ?? 0
        start = rows[..<index].filter { !moving.contains($0.id) }.count
    }

    /// Where among `rest` the dragged rows land; where they started while the pointer is outside the list.
    var gap: Int {
        isOutside ? start : min(max(start + Int((translation / LayersPanel.rowHeight).rounded()), 0), rest.count)
    }

    /// The row in `rows` the dragged rows go before, or `nil` if they'd land where they are.
    func destination(in rows: [LayerRow]) -> Int? {
        LayerList.destination(of: rows.map(\.id), moving: moving, gap: gap)
    }
}

private struct LayerRowView<Grip: Gesture>: View {
    let row: LayerRow
    let isSelected: Bool
    let isFocused: Bool
    let isLifted: Bool
    let grip: Grip
    let onHide: () -> Void
    let onLock: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brutal.ink.opacity(isLifted ? 1 : 0.45))
                .frame(width: 16, height: Self.height)
                .contentShape(Rectangle())
                .pointerStyle(isLifted ? .grabActive : .grabIdle)
                .gesture(grip)
                .accessibilityLabel(Text("Drag to reorder"))
            Image(systemName: row.symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 18)
            Text(row.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            RowButton(symbol: row.isLocked ? "lock.fill" : "lock.open", isOn: row.isLocked, label: row.isLocked ? "Unlock" : "Lock", action: onLock)
            RowButton(symbol: row.isHidden ? "eye.slash" : "eye", isOn: row.isHidden, label: row.isHidden ? "Show" : "Hide", action: onHide)
            RowButton(symbol: "trash", isOn: false, label: "Delete", action: onDelete)
                .disabled(row.isLocked)
        }
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .frame(height: Self.height)
        .foregroundStyle(Brutal.ink)
        .opacity(row.isHidden && !isLifted ? 0.45 : 1)
        .background { background }
        .scaleEffect(isLifted ? 1.04 : 1)
        .shadow(color: .black.opacity(isLifted ? 0.25 : 0), radius: 8, y: 4)
    }

    private static var height: CGFloat { LayersPanel.rowHeight - 2 }

    @ViewBuilder
    private var background: some View {
        if isLifted {
            Color.clear.brutalSurface(isSelected ? Brutal.yellow : Color.white, radius: 7, shadow: 2, border: 2)
        } else if isSelected {
            RoundedRectangle(cornerRadius: 7, style: .circular).fill(Brutal.yellow.opacity(isFocused ? 1 : 0.5))
        }
    }
}

/// Shown dimmed until set or hovered, so an unlocked, visible row isn't cluttered.
private struct RowButton: View {
    let symbol: String
    let isOn: Bool
    let label: String
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 20, height: 20)
                .opacity(isOn || (isHovered && isEnabled) ? 1 : isEnabled ? 0.4 : 0.15)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(label))
        .brutalTip(label)
    }
}
