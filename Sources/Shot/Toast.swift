import AppKit
import Carbon.HIToolbox
import ShotCore
import SwiftUI

@MainActor
enum Toast {
    private static var panel: FloatingPanelWindow?
    private static var hideTask: Task<Void, Never>?
    private static var duration: Duration?
    private static var undoable: PendingAction?
    private static var shown: ToastText?
    private static var action: ToastView.Action?
    private static var tick: ToastView.Tick?
    /// Where the panel rests once it has arrived. Changes work from this, not from `panel.frame`, which is still rising
    /// for the first 240 ms.
    private static var restingFrame = NSRect.zero
    /// The Quick Access corner the toast sits in, which it keeps its outer edge against as it changes size.
    private static var side = QuickAccessPosition.left
    fileprivate static let font = ScaledFont.scaled(13, weight: .medium)
    fileprivate static let actionFont = ScaledFont.scaled(12, weight: .semibold)
    fileprivate static let height: CGFloat = 36
    fileprivate static let barWidth: CGFloat = 96

    /// Shows `message` for something that didn't happen or went wrong, long enough to read.
    static func error(_ message: LocalizedStringResource) {
        error(String(localized: message))
    }

    /// An error whose text is already localized, such as an error's `localizedDescription`.
    @_disfavoredOverload
    static func error<S: StringProtocol>(_ message: S) {
        show(String(message), duration: .seconds(5))
    }

    /// Shows `message`; `duration` nil keeps it visible until the next call. The pointer holds it, and a click dismisses it.
    /// With `undoable`, the toast offers Undo, which ⌘Z also presses from any app while the toast shows, and the action
    /// commits once the toast goes away any other way.
    /// With `cancel`, it offers Cancel for the work it describes. With `reveal`, it offers Show, which selects that file in Finder.
    static func show(_ message: LocalizedStringResource, duration: Duration? = .seconds(1.5), undoable: PendingAction? = nil, cancel: (() -> Void)? = nil, reveal: URL? = nil) {
        show(String(localized: message), duration: duration, undoable: undoable, cancel: cancel, reveal: reveal)
    }

    /// A toast whose text is already localized.
    @_disfavoredOverload
    static func show<S: StringProtocol>(_ message: S, duration: Duration? = .seconds(1.5), undoable: PendingAction? = nil, cancel: (() -> Void)? = nil, reveal: URL? = nil) {
        present(String(message), duration: duration, undoable: undoable, cancel: cancel, reveal: reveal, tick: nil)
    }

    /// Shows `message` after a copy or save worked, led by an accent tick that draws itself. `drawsTick` false shows the
    /// tick already drawn, for when another moment has just played, such as the viewfinder snapping in over a capture.
    static func done(_ message: LocalizedStringResource, drawsTick: Bool = true, duration: Duration? = .seconds(1.5)) {
        done(String(localized: message), drawsTick: drawsTick, duration: duration)
    }

    /// A done toast whose text is already localized.
    @_disfavoredOverload
    static func done<S: StringProtocol>(_ message: S, drawsTick: Bool = true, duration: Duration? = .seconds(1.5)) {
        present(String(message), duration: duration, undoable: nil, cancel: nil, reveal: nil, tick: drawsTick ? .draws : .drawn)
    }

    private static func present(_ message: String, duration: Duration?, undoable: PendingAction?, cancel: (() -> Void)?, reveal: URL?, tick: ToastView.Tick?) {
        settle()
        self.undoable = undoable
        let panel = panel ?? makePanel()
        if let undoable {
            // The panel never becomes key, so ⌘Z can't reach it through the responder chain.
            HotkeyCenter.shared.registerTemporary(KeyCombo(keyCode: UInt32(kVK_ANSI_Z), modifiers: KeyCombo.command)) {
                undoable.undo()
                hide()
            }
        }
        let action: ToastView.Action? = if let undoable {
            ToastView.Action(title: String(localized: "Undo"), key: "⌘Z") { undoable.undo(); hide() }
        } else if let cancel {
            ToastView.Action(title: String(localized: "Cancel"), perform: cancel)
        } else if let reveal {
            ToastView.Action(title: String(localized: "Show")) { NSWorkspace.shared.activateFileViewerSelecting([reveal]); hide() }
        } else {
            nil
        }
        self.action = action
        self.tick = tick
        let size = size(of: message, fraction: nil, action: action, tick: tick)
        let text = ToastText(message: message)
        shown = text
        panel.contentView = NSView(hosting: ToastView(text: text, action: action, tick: tick, hold: { hold($0) }, dismiss: { hide() }))
        let screen = NSScreen.underPointer ?? NSScreen.main ?? NSScreen.screens[0]
        side = Preferences().quickAccessPosition
        let frame = ToastLayout.frame(
            size: size,
            in: screen.visibleFrame,
            side: side,
            edgeInset: QuickAccessController.cardEdgeInset,
            cardsTop: QuickAccessController.shared.cardsTop(on: screen)
        )
        arrive(panel, at: frame)
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        self.duration = duration
        scheduleHide()
    }

    /// Shows `message` until the next call with a progress bar filled to `fraction`, from 0 to 1, changing the toast in place
    /// without announcing it, so the bar can fill without VoiceOver reading every step. Does nothing when nothing changed.
    static func progress(_ message: LocalizedStringResource, fraction: Double) {
        progress(String(localized: message), fraction: fraction)
    }

    /// Progress whose text is already localized.
    @_disfavoredOverload
    static func progress<S: StringProtocol>(_ message: S, fraction: Double) {
        let message = String(message)
        guard let panel, let shown, undoable == nil else {
            present(message, duration: nil, undoable: nil, cancel: nil, reveal: nil, tick: nil)
            self.shown?.fraction = fraction
            resize()
            return
        }
        guard shown.message != message || shown.fraction != fraction else {
            return
        }
        let resizes = shown.message != message || shown.fraction == nil
        shown.message = message
        shown.fraction = fraction
        duration = nil
        hideTask?.cancel()
        if resizes {
            resize()
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private static func resize() {
        guard let panel, let shown else {
            return
        }
        let size = size(of: shown.message, fraction: shown.fraction, action: action, tick: tick)
        place(panel, at: ToastLayout.resized(restingFrame, to: size, side: side))
    }

    /// Moves the panel straight to `frame`, replacing any arrival still running so it can't carry the panel elsewhere.
    private static func place(_ panel: FloatingPanelWindow, at frame: NSRect) {
        restingFrame = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Puts the panel at `frame`. A toast that wasn't showing springs up a few points as it fades in, or only fades with
    /// Reduce Motion; one already showing changes in place.
    private static func arrive(_ panel: FloatingPanelWindow, at frame: NSRect) {
        guard !panel.isVisible else {
            place(panel, at: frame)
            return
        }
        restingFrame = frame
        let reduced = Motion.reduced
        panel.alphaValue = 0
        panel.setFrame(reduced ? frame : frame.offsetBy(dx: 0, dy: -8), display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? Moment.reducedFade : Moment.panelArrive.duration
            context.timingFunction = reduced ? CAMediaTimingFunction(name: .easeOut) : Motion.arriveCurve
            panel.animator().alphaValue = 1
            if !reduced {
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    private static func size(of message: String, fraction: Double?, action: ToastView.Action?, tick: ToastView.Tick?) -> NSSize {
        let textSize = Preferences().textSize
        func width(_ text: String, _ font: ScaledFont, weight: NSFont.Weight) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: font.points(textSize), weight: weight)]).width.rounded(.up)
        }
        var total = (tick == nil ? ToastView.leading : ToastView.tickLeading + ToastView.tickSize + ToastView.spacing) + width(message, font, weight: .medium)
        if fraction != nil {
            total += ToastView.spacing + barWidth + ToastView.spacing + ToastView.percentWidth(textSize)
        }
        if let action {
            total += ToastView.spacing + ToastView.actionPadding * 2 + width(action.title, actionFont, weight: .semibold)
            if let key = action.key {
                total += ToastView.keyGap + width(key, actionFont, weight: .semibold)
            }
            total += ToastView.trailingWithAction
        } else {
            total += ToastView.leading
        }
        return NSSize(width: total + 2, height: height)
    }

    private static func hold(_ holding: Bool) {
        if holding {
            hideTask?.cancel()
        } else {
            scheduleHide()
        }
    }

    private static func scheduleHide() {
        hideTask?.cancel()
        guard let duration, panel != nil else {
            return
        }
        hideTask = Task {
            try? await Task.sleep(for: duration)
            if !Task.isCancelled {
                hide()
            }
        }
    }

    /// Commits what an undo toast would undo, for when Shot quits while one shows, so a discarded recording's parts are
    /// deleted rather than offered back by the recovery dialog the next time Shot opens.
    static func commitPending() {
        settle()
    }

    private static func hide() {
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        settle()
    }

    private static func settle() {
        let pending = undoable
        undoable = nil
        if pending != nil {
            HotkeyCenter.shared.unregisterTemporary()
        }
        pending?.commit()
    }

    private static func makePanel() -> FloatingPanelWindow {
        let panel = FloatingPanelWindow(contentRect: .zero)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }
}

@MainActor
@Observable
private final class ToastText {
    var message: String
    /// How far the work has got, from 0 to 1, for a toast that shows a progress bar.
    var fraction: Double?

    init(message: String) {
        self.message = message
    }
}

/// A dark pill, like the other floating panels in both appearances, with the message, any progress bar and one button.
private struct ToastView: View {
    struct Action {
        let title: String
        /// The shortcut that also presses it, shown faded after the title.
        var key: String?
        let perform: () -> Void
    }

    /// The accent tick that leads a done toast: drawing itself, or already drawn.
    enum Tick {
        case draws, drawn
    }

    static let leading: CGFloat = 14
    static let tickLeading: CGFloat = 9
    static let tickSize: CGFloat = 20
    static let trailingWithAction: CGFloat = 6
    static let spacing: CGFloat = 10
    static let actionPadding: CGFloat = 10
    static let keyGap: CGFloat = 5

    static func percentWidth(_ textSize: TextSize) -> CGFloat {
        ("100%" as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: Toast.actionFont.points(textSize), weight: .semibold)]).width.rounded(.up)
    }

    let text: ToastText
    let action: Action?
    let tick: Tick?
    let hold: (Bool) -> Void
    let dismiss: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.textSize) private var textSize

    var body: some View {
        HStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                if let tick {
                    ToastTickMark(draws: tick == .draws)
                }
                Text(text.message)
                    .font(Toast.font)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            if let fraction = text.fraction {
                BrutalProgressBar(value: fraction)
                    .frame(width: Toast.barWidth)
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.scaled(12, weight: .semibold, tabular: true))
                    .foregroundStyle(contrast == .increased ? .white : FloatingPanel.secondaryText)
                    .frame(width: Self.percentWidth(textSize), alignment: .trailing)
                    .accessibilityHidden(true)
            }
            if let action {
                Button(action: action.perform) {
                    HStack(spacing: Self.keyGap) {
                        Text(action.title)
                        if let key = action.key {
                            Text(verbatim: key).opacity(0.6).accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(ToastButtonStyle())
            }
        }
        .padding(.leading, tick == nil ? Self.leading : Self.tickLeading)
        .padding(.trailing, action == nil ? Self.leading : Self.trailingWithAction)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .floatingPanel(Capsule(), opacity: FloatingPanel.Opacity.toast)
        .contentShape(Capsule())
        .onHover(perform: hold)
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .contain)
    }
}

/// The toast's one button: a white-tinted pill, brighter while pressed.
private struct ToastButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Toast.actionFont)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, ToastView.actionPadding)
            .padding(.vertical, 4)
            .background(.white.opacity(configuration.isPressed ? 0.26 : 0.16), in: Capsule())
            .contentShape(Capsule())
    }
}

/// A 20 pt accent disc whose ink tick draws itself over 240 ms, or shows drawn with Reduce Motion. The tick is the
/// board's 24-unit path drawn 11 pt square, so its 3.4-unit stroke is about 1.6 pt.
private struct ToastTickMark: View {
    static let tickBox: CGFloat = 11

    let draws: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        Circle()
            .fill(Brutal.accent)
            .frame(width: ToastView.tickSize, height: ToastView.tickSize)
            .overlay {
                TickShape()
                    .trim(from: 0, to: progress)
                    .stroke(Color(hex: 0x16161A), style: StrokeStyle(lineWidth: TickShape.lineWidth * Self.tickBox / TickShape.units, lineCap: .round, lineJoin: .round))
                    .frame(width: Self.tickBox, height: Self.tickBox)
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
