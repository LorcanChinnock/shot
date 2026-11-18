import AppKit
import ShotCore
import SwiftUI

/// A short "Copied" or "Saved" shown where the action was taken, on the button that took it or on the Quick Access card,
/// rather than in a toast in the corner of the screen that's easy to miss. Each one has its own `id`, so doing the same
/// thing twice plays again.
struct ActionConfirmation: Equatable, Identifiable {
    /// How long a confirmation stays before the button or card goes back to how it was.
    static let duration: Duration = .seconds(1.4)

    let id = UUID()
    let message: String

    init(_ message: LocalizedStringResource) {
        self.message = String(localized: message)
    }

    /// Reads `message` to VoiceOver, which can't see the button or card change.
    @MainActor
    func announce() {
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}

/// Which of a window's buttons is confirming what it did, and what it says. One at a time: a new confirmation replaces
/// the last, and each clears itself after `ActionConfirmation.duration`.
@MainActor
@Observable
final class ActionConfirmations<Target: Hashable> {
    private(set) var target: Target?
    private(set) var current: ActionConfirmation?
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    func show(_ message: LocalizedStringResource, on target: Target) {
        let confirmation = ActionConfirmation(message)
        self.target = target
        current = confirmation
        confirmation.announce()
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: ActionConfirmation.duration)
            guard !Task.isCancelled, let self, self.current?.id == confirmation.id else {
                return
            }
            self.target = nil
            self.current = nil
        }
    }

    /// The confirmation `target` shows, if it's the one confirming.
    func on(_ target: Target) -> ActionConfirmation? {
        self.target == target ? current : nil
    }
}

// MARK: On a button

extension View {
    /// Plays a button's confirmation: the button bounces as `ConfirmableLabel` turns its label into a tick, and a small
    /// dark bubble with the message pops up just under it, then fades. Nothing changes size, so the toolbar never moves.
    /// Goes on the button, outside its style, so the bounce scales the whole button. Reduce Motion fades instead.
    func confirmationFeedback(_ confirmation: ActionConfirmation?) -> some View {
        modifier(ConfirmationFeedback(confirmation: confirmation))
    }
}

private struct ConfirmationFeedback: ViewModifier {
    let confirmation: ActionConfirmation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Bounces only as a confirmation arrives, not as it goes.
        let bounce: CGFloat = confirmation != nil && !reduceMotion ? 1 : 0
        content
            .keyframeAnimator(initialValue: CGFloat(1), trigger: confirmation?.id) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                // Squash, overshoot and settle, inside the 240 ms a moment gets.
                CubicKeyframe(1 - 0.08 * bounce, duration: 0.06)
                SpringKeyframe(1 + 0.07 * bounce, duration: 0.1)
                SpringKeyframe(1, duration: 0.08)
            }
            .overlay(alignment: .bottom) {
                ZStack {
                    if let confirmation {
                        ConfirmationBubble(message: confirmation.message)
                            .id(confirmation.id)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .top).combined(with: .opacity))
                    }
                }
                // The bubble's top sits 6 pt under the button, outside its frame, so it takes no room.
                .alignmentGuide(.bottom) { $0[.top] - 6 }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .animation(reduceMotion ? Motion.fade : .spring(duration: Moment.panelArrive.duration, bounce: 0.35), value: confirmation?.id)
    }
}

/// The message under a confirming button: one line of 12 pt semibold white on a dark floating pill.
private struct ConfirmationBubble: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.scaled(12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .floatingPanel(Capsule(), opacity: FloatingPanel.Opacity.toast)
            .fixedSize()
    }
}

/// A button's label, which becomes a tick drawing itself while the button confirms. The label stays laid out underneath,
/// so the button keeps its size.
struct ConfirmableLabel<Label: View>: View {
    let confirmation: ActionConfirmation?
    @ViewBuilder let label: Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .opacity(confirmation == nil ? 1 : 0)
            .overlay {
                if let confirmation {
                    DrawnTick(draws: true)
                        .frame(width: 12, height: 12)
                        .id(confirmation.id)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }
            }
    }
}

// MARK: Ticks

/// The board's tick, drawn in the foreground style, drawing itself over 240 ms (`Moment.tick`) when `draws`, or shown
/// drawn with Reduce Motion.
struct DrawnTick: View {
    let draws: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            TickShape()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: TickShape.lineWidth * proxy.size.width / TickShape.units, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
        .onAppear {
            guard draws, let animation = Motion.animation(.tick, reduceMotion: reduceMotion) else {
                progress = 1
                return
            }
            withAnimation(animation) { progress = 1 }
        }
    }
}

/// A 20 pt accent disc holding an ink tick 11 pt square, so its 3.4-unit stroke is about 1.6 pt. It leads a done toast
/// and a Quick Access card's confirmation.
struct TickMark: View {
    static let size: CGFloat = 20
    static let tickBox: CGFloat = 11

    let draws: Bool

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: Self.size, height: Self.size)
            .overlay {
                DrawnTick(draws: draws)
                    .foregroundStyle(Color(hex: 0x16161A))
                    .frame(width: Self.tickBox, height: Self.tickBox)
            }
            .accessibilityHidden(true)
    }
}

/// The board's tick, `M5 12l5 5 9-10` in a 24-unit box, drawn from its short stroke to its long one, so trimming it draws
/// it as a pen would.
private struct TickShape: Shape {
    static let units: CGFloat = 24
    static let lineWidth: CGFloat = 3.4

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / Self.units, y: rect.minY + rect.height * y / Self.units)
        }
        var path = Path()
        path.move(to: point(5, 12))
        path.addLine(to: point(10, 17))
        path.addLine(to: point(19, 7))
        return path
    }
}
