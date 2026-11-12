import AppKit
import ShotCore
import SwiftUI

struct LayerRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let symbol: String
    let isHidden: Bool
    let isLocked: Bool
    /// Whether it's a placed image, which can be cropped.
    let isImage: Bool
    /// Whether it's a placed image with a crop of its own, which its badge shows.
    let isCropped: Bool
}

/// The crop of the whole image, listed above the layers while there is one.
struct FrameRow: Equatable {
    let isHidden: Bool
    /// Whether the crop tool is adjusting it.
    let isSelected: Bool
    /// The crop's shape or size on the right, from ShotCore's `FrameRowDetail`.
    let detail: String
}

/// The photo editor's annotations as a stack of layers, frontmost first, with the crop pinned above them and the image
/// locked at the bottom, from Edit › Image editor · crop and combine: a side panel flush with the canvas.
struct LayersPanel: View {
    static let width: CGFloat = 256
    /// A row's 28 pt and the 1 pt gap after it.
    nonisolated static let rowHeight: CGFloat = 29
    private static let space = "layers"
    /// How far a drag scrolls the list each frame with the pointer at its edge.
    private static let edgeScrollStep: CGFloat = 10

    let rows: [LayerRow]
    let frame: FrameRow?
    @Binding var selection: Set<UUID>
    /// The rows at the offsets moved to before the row at the destination, as `List`'s `onMove` passes them.
    let onMove: (IndexSet, Int) -> Void
    let onHide: (Set<UUID>, Bool) -> Void
    let onLock: (Set<UUID>, Bool) -> Void
    /// Layer `id` was given a name; an empty one goes back to the automatic name.
    let onRename: (UUID, String) -> Void
    let onDuplicate: (Set<UUID>) -> Void
    let onDelete: (Set<UUID>) -> Void
    /// Crop Image or a crop badge was chosen for the placed image with this id.
    let onCropImage: (UUID) -> Void
    let onResetImageCrop: (UUID) -> Void
    let onSelectFrame: () -> Void
    let onHideFrame: (Bool) -> Void
    let onDeleteFrame: () -> Void
    /// A tool's key was pressed while the list had focus and no name was being edited.
    let onTool: (EditorTool) -> Void

    @FocusState private var isFocused: Bool
    @State private var drag: RowDrag?
    /// Set by Escape, so the rest of that drag does nothing.
    @State private var dragCancelled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var escapeMonitor: Any?
    @State private var listSize: CGSize = .zero
    @State private var position = ScrollPosition()
    @State private var scroll = ListScroll()
    /// Scrolls the list while a drag is held near its top or bottom.
    @State private var edgeScroll: Task<Void, Never>?
    /// Where a ⇧-click range starts.
    @State private var anchor: UUID?
    /// The layer whose name is being edited in place.
    @State private var renaming: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            if let frame {
                FrameRowView(row: frame, onSelect: onSelectFrame, onHide: { onHideFrame(!frame.isHidden) }, onDelete: onDeleteFrame)
                PanelHairline().padding(.horizontal, 4).padding(.vertical, 6)
            }
            ScrollView {
                ZStack(alignment: .top) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(drag.map { $0.rest.count + 1 } ?? rows.count) * Self.rowHeight, alignment: .top)
            }
            .scrollIndicators(.automatic)
            .scrollPosition($position)
            .onScrollGeometryChange(for: ListScroll.self) { geometry in
                ListScroll(offset: geometry.contentOffset.y, content: geometry.contentSize.height, viewport: geometry.containerSize.height)
            } action: { _, new in
                scroll = new
                drag?.scrolled = new.offset - (drag?.startOffset ?? 0)
            }
            .coordinateSpace(.named(Self.space))
            .onGeometryChange(for: CGSize.self, of: \.size) { listSize = $0 }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onDeleteCommand {
                if frame?.isSelected == true {
                    onDeleteFrame()
                } else {
                    onDelete(selection)
                }
            }
            .onMoveCommand(perform: moveSelection)
            .onKeyPress(.return) {
                guard renaming == nil, selection.count == 1, let id = selection.first, rows.contains(where: { $0.id == id }) else {
                    return .ignored
                }
                renaming = id
                return .handled
            }
            // Tool keys work here too, as they do on the canvas.
            .onKeyPress(phases: .down) { press in
                guard renaming == nil, press.modifiers.isDisjoint(with: [.command, .control, .option]), let tool = EditorTool(key: press.characters) else {
                    return .ignored
                }
                onTool(tool)
                return .handled
            }
            .overlay {
                if rows.isEmpty {
                    EmptyLayers().allowsHitTesting(false)
                }
            }
            PanelHairline().padding(.vertical, 6)
            footer
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .sidePanel(width: Self.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Layers"))
        .onDisappear(perform: stopDragging)
    }

    /// "Layers" in 13 pt bold, and its shortcut in the tertiary text on the right.
    private var header: some View {
        HStack {
            Text("Layers")
                .font(.scaled(13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(verbatim: "⌘L")
                .font(.scaled(11))
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    /// The screenshot under every layer, which can't be moved or hidden.
    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: "photo")
                .font(.scaled(12, weight: .medium))
                .frame(width: 16)
            Text("Screenshot")
                .font(.scaled(13))
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "lock.fill")
                .font(.scaled(10, weight: .semibold))
                .foregroundStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink))
                .frame(width: 20)
        }
        .foregroundStyle(ContrastAware(standard: Theme.secondaryText, increased: Theme.ink))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Screenshot, locked"))
    }

    private func rowView(_ row: LayerRow) -> some View {
        let lifted = drag?.id == row.id
        let carried = drag.map { $0.moving.contains(row.id) && !lifted } ?? false
        return LayerRowView(
            row: row,
            isSelected: selection.contains(row.id),
            isLifted: lifted,
            isRenaming: renaming == row.id,
            grip: grip(for: row),
            onHide: { onHide([row.id], !row.isHidden) },
            onLock: { onLock([row.id], !row.isLocked) },
            onDelete: { onDelete([row.id]) },
            onCrop: { onCropImage(row.id) },
            onRename: { name in
                renaming = nil
                if let name {
                    onRename(row.id, name)
                }
            }
        )
        .frame(height: Self.rowHeight, alignment: .top)
        .contentShape(Rectangle())
        // One gesture, so a click selects at once instead of waiting out the double-click interval; the second click renames.
        .onTapGesture {
            guard renaming != row.id else {
                return
            }
            if NSApp.currentEvent?.clickCount == 2, NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) {
                selection = [row.id]
                anchor = row.id
                renaming = row.id
            } else {
                click(row.id)
            }
        }
        .contextMenu { menu(for: selection.contains(row.id) ? selection : [row.id]) }
        // Pressing selects the layer, as a click does. Its own action, since the tap gesture reads a mouse event's click count.
        .accessibilityAction(.default) {
            isFocused = true
            selection = [row.id]
            anchor = row.id
        }
        .accessibilityAction(named: Text("Rename")) {
            selection = [row.id]
            renaming = row.id
        }
        // The grip only drags, so VoiceOver moves a layer one place at a time.
        .accessibilityActions {
            if let index = rows.firstIndex(where: { $0.id == row.id }) {
                if index > 0 {
                    Button("Move Up") { onMove(IndexSet(integer: index), index - 1) }
                }
                if index < rows.count - 1 {
                    Button("Move Down") { onMove(IndexSet(integer: index), index + 2) }
                }
            }
        }
        // Carried rows ride under the lifted one, which fades while a drop would cancel.
        .opacity(carried ? 0 : lifted && drag?.isOutside == true ? 0.5 : 1)
        // The lifted row follows the pointer; the others glide to open the gap.
        .offset(y: y(of: row.id))
        .animation(lifted || reduceMotion ? nil : .snappy(duration: 0.2), value: drag?.gap)
        .zIndex(lifted ? 1 : 0)
    }

    @ViewBuilder
    private func menu(for ids: Set<UUID>) -> some View {
        let chosen = rows.filter { ids.contains($0.id) }
        if !chosen.isEmpty {
            if chosen.count == 1 {
                Button("Rename") {
                    selection = ids
                    renaming = chosen[0].id
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            if chosen.count == 1, chosen[0].isImage, !chosen[0].isLocked {
                Button("Crop Image") { onCropImage(chosen[0].id) }
                if chosen[0].isCropped {
                    Button("Reset Crop") { onResetImageCrop(chosen[0].id) }
                }
                Divider()
            }
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
            return CGFloat(drag.start) * Self.rowHeight + drag.offset
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
                    withAnimation(glide(0.2)) {
                        drag = RowDrag(id: row.id, moving: movingIDs(grabbing: row.id), rows: rows, startOffset: scroll.offset)
                    }
                    watchEscape()
                }
                // A row past the top or bottom still drops, so the list can scroll under it.
                drag?.isOutside = !CGRect(origin: .zero, size: listSize).insetBy(dx: 0, dy: -Self.rowHeight).contains(value.location)
                drag?.translation = value.translation.height
                drag?.pointer = value.location.y
                scrollAtEdges()
            }
            .onEnded { _ in
                defer { dragCancelled = false }
                guard !dragCancelled, let drag else {
                    return
                }
                stopDragging()
                withAnimation(glide(0.25)) {
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

    /// Scrolls towards the edge the pointer is held near, faster the closer it gets, until it moves away or the list ends.
    private func scrollAtEdges() {
        guard edgeScroll == nil else {
            return
        }
        edgeScroll = Task {
            while !Task.isCancelled, let drag, !drag.isOutside {
                let speed = EdgeScroll.speed(at: drag.pointer, length: listSize.height, zone: Self.rowHeight)
                let next = EdgeScroll.offset(scroll.offset, by: speed * Self.edgeScrollStep, content: scroll.content, viewport: scroll.viewport)
                guard next != scroll.offset else {
                    break
                }
                position.scrollTo(y: next)
                try? await Task.sleep(for: .milliseconds(16))
            }
            edgeScroll = nil
        }
    }

    private func stopDragging() {
        stopWatchingEscape()
        edgeScroll?.cancel()
        edgeScroll = nil
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

    /// Rows glide aside while one is dragged, or jump straight there with Reduce Motion.
    private func glide(_ duration: Double) -> Animation? {
        reduceMotion ? nil : .snappy(duration: duration)
    }

    private func cancelDrag() {
        stopDragging()
        guard drag != nil else {
            return
        }
        dragCancelled = true
        withAnimation(glide(0.25)) {
            drag = nil
        }
    }
}

/// The Frame row: click it to adjust the crop. Unlike a layer it can't be moved, locked or duplicated. While the crop tool
/// adjusts it, it's yellow with an ink edge, as the selected tool is.
private struct FrameRowView: View {
    let row: FrameRow
    let onSelect: () -> Void
    let onHide: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "crop")
                .font(.scaled(12, weight: .semibold))
                .frame(width: 16)
                .accessibilityHidden(true)
            Text("Frame")
                .font(.scaled(13, weight: row.isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: row.detail)
                .font(.scaled(11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(row.isSelected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(ContrastAware(standard: Theme.tertiaryText, increased: Theme.ink)))
            HStack(spacing: 0) {
                RowButton(symbol: row.isHidden ? "eye.slash" : "eye", isOn: row.isHidden, label: row.isHidden ? "Show" : "Hide", action: onHide)
                RowButton(symbol: "trash", isOn: false, label: "Delete", isShown: isHovered, action: onDelete)
            }
        }
        // As a layer row's, so the eyes line up.
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: layerRowHeight)
        .foregroundStyle(Theme.ink)
        .opacity(row.isHidden ? (contrast == .increased ? 0.8 : 0.5) : 1)
        .inkOnFill(row.isSelected ? Theme.yellow : nil)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
            if row.isSelected {
                shape.fill(Theme.yellow).inkBorder(shape, width: 1.5)
            } else if isHovered {
                shape.fill(Theme.hover)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Delete", action: onDelete)
            Button(row.isHidden ? "Show" : "Hide", action: onHide)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Frame, \(row.detail)"))
        .accessibilityAddTraits(row.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: Text("Delete"), onDelete)
    }
}

/// A 1 pt hairline between the panel's parts.
private struct PanelHairline: View {
    var body: some View {
        Rectangle()
            .fill(ContrastAware(standard: Theme.hairline, increased: Theme.ink.opacity(0.6)))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// What the list shows before anything is drawn.
private struct EmptyLayers: View {
    var body: some View {
        EmptyState(symbol: "scribble.variable", title: "Nothing drawn yet", message: "Pick a tool, or press A for an arrow.")
    }
}

private struct ListScroll: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var viewport: CGFloat = 0
}

/// A drag of one row, carrying the others in `moving` with it.
private struct RowDrag {
    let id: UUID
    let moving: Set<UUID>
    /// The rows that stay, in order.
    let rest: [UUID]
    /// The dragged row's place among `rest`, where it started.
    let start: Int
    /// How far the list was scrolled when the drag began.
    let startOffset: CGFloat
    var translation: CGFloat = 0
    /// How far the list has scrolled since the drag began.
    var scrolled: CGFloat = 0
    /// The pointer's height in the visible list.
    var pointer: CGFloat = 0
    var isOutside = false

    init(id: UUID, moving: Set<UUID>, rows: [LayerRow], startOffset: CGFloat) {
        self.id = id
        self.moving = moving
        self.startOffset = startOffset
        rest = rows.map(\.id).filter { !moving.contains($0) }
        let index = rows.firstIndex { $0.id == id } ?? 0
        start = rows[..<index].filter { !moving.contains($0.id) }.count
    }

    /// How far the dragged row has moved through the list.
    var offset: CGFloat {
        translation + scrolled
    }

    /// Where among `rest` the dragged rows land; where they started while the pointer is outside the list.
    var gap: Int {
        isOutside ? start : min(max(start + Int((offset / LayersPanel.rowHeight).rounded()), 0), rest.count)
    }

    /// The row in `rows` the dragged rows go before, or `nil` if they'd land where they are.
    func destination(in rows: [LayerRow]) -> Int? {
        LayerList.destination(of: rows.map(\.id), moving: moving, gap: gap)
    }
}

/// A row's height, less the 1 pt gap after it.
private let layerRowHeight: CGFloat = 28

private struct LayerRowView<Grip: Gesture>: View {
    let row: LayerRow
    let isSelected: Bool
    let isLifted: Bool
    let isRenaming: Bool
    let grip: Grip
    let onHide: () -> Void
    let onLock: () -> Void
    let onDelete: () -> Void
    let onCrop: () -> Void
    /// The name typed into the field, or `nil` when Escape cancelled it.
    let onRename: (String?) -> Void
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 9) {
            GripDots()
                .foregroundStyle(Theme.faded(isLifted ? 0.8 : 0.4))
                .frame(width: 10, height: layerRowHeight)
                .contentShape(Rectangle())
                .pointerStyle(isLifted ? .grabActive : .grabIdle)
                .gesture(grip)
                // VoiceOver moves a layer with the row's Move Up and Move Down actions instead.
                .accessibilityHidden(true)
            Image(systemName: row.symbol)
                .font(.scaled(12, weight: .medium))
                .foregroundStyle(ContrastAware(standard: Theme.ink.opacity(0.85), increased: Theme.ink))
                .frame(width: 16)
                .accessibilityHidden(true)
            if isRenaming {
                LayerNameField(name: row.name, fontSize: 13, onCommit: { onRename($0) }, onCancel: { onRename(nil) })
            } else {
                Text(row.name)
                    .font(.scaled(13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if row.isCropped {
                CropBadge(action: onCrop)
                    .disabled(row.isLocked)
            }
            HStack(spacing: 0) {
                // The lock shows while it's set; the lock and bin of an unlocked row show while the pointer is on it.
                RowButton(symbol: row.isLocked ? "lock.fill" : "lock.open", isOn: row.isLocked, label: row.isLocked ? "Unlock" : "Lock", isShown: row.isLocked || isHovered, action: onLock)
                RowButton(symbol: row.isHidden ? "eye.slash" : "eye", isOn: row.isHidden, label: row.isHidden ? "Show" : "Hide", action: onHide)
                RowButton(symbol: "trash", isOn: false, label: "Delete", isShown: isHovered, action: onDelete)
                    .disabled(row.isLocked)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: layerRowHeight)
        .foregroundStyle(Theme.ink)
        // Lighter under Increase Contrast too, but enough that the eye in a hidden row keeps 3:1.
        .opacity(row.isHidden && !isLifted ? (contrast == .increased ? 0.8 : 0.5) : 1)
        .background { background }
        .scaleEffect(isLifted ? 1.03 : 1)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(row.name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // The lock and bin hide until the pointer is on the row, so VoiceOver reaches them as actions too.
        .accessibilityAction(named: Text(row.isLocked ? "Unlock" : "Lock"), onLock)
        .accessibilityActions {
            if !row.isLocked {
                Button("Delete", action: onDelete)
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
        if isLifted {
            Color.clear
                .depth(.float, fill: Theme.group, radius: Theme.Radius.control)
                .overlay { if isSelected { selectionFill(shape) } }
        } else if isSelected {
            selectionFill(shape)
        } else if isHovered {
            shape.fill(Theme.hover)
        }
    }

    /// Selection blue at 14% with a 1 pt edge at 35%, solid under Increase Contrast.
    private func selectionFill(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(Theme.selection.opacity(0.14))
            .inkBorder(shape, width: 1, color: Theme.selection.opacity(contrast == .increased ? 1 : 0.35))
    }
}

/// The drag handle: two columns of three dots, 2.4 pt across, as on the board.
private struct GripDots: View {
    var body: some View {
        VStack(spacing: 1.6) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2.6) {
                    Circle().frame(width: 2.4, height: 2.4)
                    Circle().frame(width: 2.4, height: 2.4)
                }
            }
        }
    }
}

/// The Crop badge on a placed image with a crop of its own: click it to adjust the crop.
private struct CropBadge: View {
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Text("Crop")
                .font(.scaled(10, weight: .semibold))
                .foregroundStyle(ContrastAware(standard: Theme.ink.opacity(0.85), increased: Theme.ink))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.ink.opacity(contrast == .increased ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.tiny, style: .circular))
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Adjust crop"))
        .themeTip("Adjust crop")
    }
}

/// A layer's name edited in place, pre-filled and selected: Return or clicking away commits it, and Escape cancels.
struct LayerNameField: View {
    let name: String
    let fontSize: CGFloat
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String
    /// Set once it has committed or cancelled, so losing focus as it goes doesn't commit again.
    @State private var isDone = false
    @FocusState private var isFocused: Bool

    init(name: String, fontSize: CGFloat, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.name = name
        self.fontSize = fontSize
        self.onCommit = onCommit
        self.onCancel = onCancel
        _text = State(initialValue: name)
    }

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .font(.scaled(fontSize, weight: .semibold))
            .lineLimit(1)
            .focused($isFocused)
            .themeField(focused: isFocused)
            .onSubmit { finish(commit: true) }
            .onExitCommand { finish(commit: false) }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    finish(commit: true)
                }
            }
            // Focus once it's in the window; AppKit selects a field's text as it takes focus.
            .task { isFocused = true }
    }

    private func finish(commit: Bool) {
        guard !isDone else {
            return
        }
        isDone = true
        if commit {
            onCommit(text)
        } else {
            onCancel()
        }
    }
}

/// A row's eye, lock or bin. Unset, it's in a quieter grey; `isShown` false leaves its room empty until the pointer is on
/// the row, so a plain row shows only its eye, as on the board.
private struct RowButton: View {
    let symbol: String
    let isOn: Bool
    let label: LocalizedStringResource
    var isShown = true
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.scaled(11, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.ink.opacity(opacity))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(isShown)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(label))
        .themeTip(label)
    }

    private var opacity: Double {
        let increased = contrast == .increased
        guard isEnabled else { return increased ? 0.3 : 0.2 }
        if isOn || isHovered { return 1 }
        return increased ? 0.75 : 0.5
    }
}
