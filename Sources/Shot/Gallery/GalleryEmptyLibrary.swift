import AppKit
import ShotCore
import SwiftUI

/// What the gallery shows before anything is saved (Library & Settings › Gallery · preview and empty state, right): a
/// dashed box where the first capture will go, an arrow drawing itself down to the screenshot shortcut, what to do, and
/// a button to pick another save folder. Reduce Motion leaves the arrow drawn and still.
struct GalleryEmptyLibrary: View {
    let model: GalleryModel
    @Setting private var screenshotKeys: String
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.textSize) private var textSize

    init(model: GalleryModel) {
        self.model = model
        _screenshotKeys = Setting(wrappedValue: ShotAction.screenshot.defaultCombo(replacingSystemScreenshots: Preferences().replacesSystemScreenshots)?.encoded ?? "",
                                  PreferenceKey.hotkey(.screenshot))
    }

    private var increased: Bool { contrast == .increased }
    private var combo: KeyCombo? { KeyCombo(encoded: screenshotKeys) }

    var body: some View {
        // A short window keeps the words and the button, and drops the box and the arrow first.
        ViewThatFits(in: .vertical) {
            content(drawing: true)
            content(drawing: false)
            ScrollView { content(drawing: false).frame(maxWidth: .infinity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { DotGrid() }
    }

    private func content(drawing: Bool) -> some View {
        VStack(spacing: 18) {
            if drawing {
                FirstCaptureBox()
                if combo != nil {
                    DrawnArrow()
                }
            }
            if let combo {
                ShortcutKeycaps(combo: combo)
            }
            VStack(spacing: 6) {
                Text("Take a screenshot to start your library")
                    .font(.scaled(17, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Everything Shot saves to \(model.folderPath) appears here, and you can search the text inside it.")
                    .font(.scaled(13))
                    .lineSpacing(3)
                    .foregroundStyle(increased ? Theme.ink : Theme.secondaryText)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: (320 * CGFloat(textSize.scale)).rounded())
            Button("Choose a different folder…") {
                model.chooseFolder(in: NSApp.keyWindow)
            }
            .buttonStyle(ThemeButtonStyle())
            .help(String(localized: "Pick the folder Shot saves captures to, as in Settings › General"))
        }
        .padding(24)
    }
}

/// The 220 × 140 dashed box where the first capture will go, with the note set in the app's own type (spec rule 7).
private struct FirstCaptureBox: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.textSize) private var textSize

    var body: some View {
        let scale = CGFloat(textSize.scale)
        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .circular)
            .stroke(Theme.ink.opacity(contrast == .increased ? 0.6 : 0.25), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            .frame(width: (220 * scale).rounded(), height: (140 * scale).rounded())
            .overlay {
                Text("Your first capture goes here")
                    .font(.scaled(15, weight: .semibold))
                    .foregroundStyle(contrast == .increased ? Theme.ink : Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .accessibilityHidden(true)
    }
}

/// The red arrow from the box down to the keys. It draws itself in half a second every three, and stays drawn with
/// Reduce Motion. Between draws nothing animates, so the window is idle most of the time.
private struct DrawnArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                ArrowShape(drawn: 1)
            } else {
                ArrowShape(drawn: 0)
                    .phaseAnimator([0.0, 1.0]) { _, phase in
                        ArrowShape(drawn: phase)
                    } animation: { phase in
                        // To drawn: wait, then draw. Back to hidden: hold the drawn arrow, then start again at once.
                        phase == 1 ? .easeInOut(duration: 0.5).delay(0.45) : .linear(duration: 0.01).delay(2.05)
                    }
            }
        }
        .frame(width: 60, height: 44)
        .accessibilityHidden(true)
    }
}

/// The board's arrow, 60 × 44: a curved stroke traced to `drawn` of its length, and a head that appears once the
/// stroke reaches it, aimed along the curve's last stretch.
private struct ArrowShape: View {
    var drawn: Double

    var body: some View {
        ZStack {
            ArrowStroke(drawn: drawn)
                .stroke(Theme.record, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ArrowHead(drawn: drawn)
                .fill(Theme.record)
        }
    }
}

/// The curve, and the head's points from its end and its direction there.
private enum ArrowGeometry {
    static let start = CGPoint(x: 30, y: 4)
    static let control1 = CGPoint(x: 18, y: 14)
    static let control2 = CGPoint(x: 22, y: 28)
    static let end = CGPoint(x: 30, y: 36)

    static var curve: Path {
        Path { path in
            path.move(to: start)
            path.addCurve(to: end, control1: control1, control2: control2)
        }
    }

    static var head: Path {
        let dx = end.x - control2.x, dy = end.y - control2.y
        let length = (dx * dx + dy * dy).squareRoot()
        let along = CGPoint(x: dx / length, y: dy / length)
        let across = CGPoint(x: along.y, y: -along.x)
        let tip = CGPoint(x: end.x + along.x * 6, y: end.y + along.y * 6)
        let base = CGPoint(x: end.x - along.x * 4, y: end.y - along.y * 4)
        return Path { path in
            path.move(to: tip)
            path.addLine(to: CGPoint(x: base.x + across.x * 6.5, y: base.y + across.y * 6.5))
            path.addLine(to: CGPoint(x: base.x - across.x * 6.5, y: base.y - across.y * 6.5))
            path.closeSubpath()
        }
    }
}

/// Animatable, so each frame of a draw traces a little more of the curve.
private struct ArrowStroke: Shape {
    var drawn: Double
    var animatableData: Double {
        get { drawn }
        set { drawn = newValue }
    }

    func path(in rect: CGRect) -> Path {
        drawn <= 0 ? Path() : ArrowGeometry.curve.trimmedPath(from: 0, to: min(drawn, 1))
    }
}

/// Shows only for the last part of a draw, so the head never floats without its line.
private struct ArrowHead: Shape {
    var drawn: Double
    var animatableData: Double {
        get { drawn }
        set { drawn = newValue }
    }

    func path(in rect: CGRect) -> Path {
        drawn >= 0.92 ? ArrowGeometry.head : Path()
    }
}

/// The screenshot shortcut from Settings as big ink keycaps, ⇧ in the accent as on the board.
private struct ShortcutKeycaps: View {
    let combo: KeyCombo

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(combo.keycaps.enumerated()), id: \.offset) { _, key in
                BigKeycap(key: key, accented: key == "⇧")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Screenshot shortcut: \(combo.displayString)"))
    }
}

/// A 22 pt heavy key on a 2 pt ink edge with a 4 pt drop.
private struct BigKeycap: View {
    let key: String
    let accented: Bool
    @Environment(\.displayScale) private var scale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .circular)
        Text(verbatim: key)
            .font(.scaled(22, weight: .heavy))
            .foregroundStyle(accented ? Color(hex: 0x16161A) : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minWidth: 36)
            .background(accented ? Theme.accent : Theme.group, in: shape)
            .inkBorder(shape, width: 2)
            .background {
                shape.fill(Theme.line).offset(y: Theme.inkOffset(4, scale: scale))
            }
            .padding(.bottom, 4)
            .fixedSize()
    }
}

/// 1 pt dots 18 pt apart in ink at 8%, behind the empty gallery.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 18
            var dots = Path()
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                    x += step
                }
                y += step
            }
            context.fill(dots, with: .color(Theme.ink.opacity(0.08)))
        }
        .accessibilityHidden(true)
    }
}

// MARK: Move to Trash

/// Asks before captures go to the Trash (Capture › Permission card… › Confirming something destructive): the first
/// thumbnails fanned out, how many, where they leave, Cancel and Move to Trash as the red ink button. Return confirms
/// and Esc cancels.
struct TrashConfirmation: View {
    let model: GalleryModel
    let request: TrashRequest
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.textSize) private var textSize

    private var count: Int { request.items.count }

    private var title: String {
        String(localized: "Move \(count) captures to the Trash?")
    }

    private var detail: String {
        count == 1
            ? String(localized: "It leaves \(model.folderPath) too. You can put it back from the Trash in Finder.")
            : String(localized: "They leave \(model.folderPath) too. You can put them back from the Trash in Finder.")
    }

    var body: some View {
        VStack(spacing: 10) {
            TrashFan(model: model, items: request.items)
                .padding(.bottom, 4)
            Text(title)
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.scaled(12.5))
                .lineSpacing(3)
                .foregroundStyle(contrast == .increased ? Theme.ink : Theme.secondaryText)
            ButtonRow(shares: [1, 1]) {
                Button { model.trashRequest = nil } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(ThemeButtonStyle())
                .keyboardShortcut(.cancelAction)
                Button { model.confirmTrash() } label: {
                    Text("Move to Trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(ThemeButtonStyle(.main, destructive: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: (300 * CGFloat(textSize.scale)).rounded())
        .background(Theme.group)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Up to three of the captures as small cards, turned a little each way and overlapping, as on the board.
private struct TrashFan: View {
    let model: GalleryModel
    let items: [GalleryItem]

    var body: some View {
        let angles = Gallery.trashFan(count: items.count)
        HStack(spacing: -30) {
            ForEach(Array(zip(items.prefix(angles.count), angles).enumerated()), id: \.offset) { _, pair in
                TrashCard(slot: model.thumbnails.slot(for: pair.0))
                    .rotationEffect(.degrees(pair.1))
                    .task { await model.thumbnails.load(pair.0) }
            }
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

/// One 54 × 40 card: the capture's thumbnail filling it, or the group colour until it's decoded.
private struct TrashCard: View {
    let slot: ThumbnailStore.Slot
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .circular)
        Theme.group
            .overlay {
                if let image = slot.thumbnail?.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 54, height: 40)
            .clipShape(shape)
            .inkBorder(shape, width: 1, color: Theme.ink.opacity(contrast == .increased ? 0.6 : 0.15))
            .shadow(color: .black.opacity(0.1), radius: 5, y: 4)
    }
}
