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
    fileprivate static let font = ScaledFont.scaled(13, weight: .medium)
    fileprivate static let actionFont = ScaledFont.scaled(12, weight: .semibold)
    fileprivate static let height: CGFloat = 34
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
        let message = String(message)
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
        let size = size(of: message, fraction: nil, action: action)
        let text = ToastText(message: message)
        shown = text
        panel.contentView = NSView(hosting: ToastView(text: text, action: action, hold: { hold($0) }, dismiss: { hide() }))
        let screen = NSScreen.underPointer ?? NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 80)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
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
            show(message, duration: nil)
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
        let size = size(of: shown.message, fraction: shown.fraction, action: action)
        panel.setFrame(NSRect(x: panel.frame.midX - size.width / 2, y: panel.frame.minY, width: size.width, height: size.height), display: true)
    }

    private static func size(of message: String, fraction: Double?, action: ToastView.Action?) -> NSSize {
        let textSize = Preferences().textSize
        func width(_ text: String, _ font: ScaledFont, weight: NSFont.Weight) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: font.points(textSize), weight: weight)]).width.rounded(.up)
        }
        var total = ToastView.leading + width(message, font, weight: .medium)
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

    private static func hide() {
        panel?.orderOut(nil)
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

    static let leading: CGFloat = 14
    static let trailingWithAction: CGFloat = 6
    static let spacing: CGFloat = 12
    static let actionPadding: CGFloat = 10
    static let keyGap: CGFloat = 5

    static func percentWidth(_ textSize: TextSize) -> CGFloat {
        ("100%" as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: Toast.actionFont.points(textSize), weight: .semibold)]).width.rounded(.up)
    }

    let text: ToastText
    let action: Action?
    let hold: (Bool) -> Void
    let dismiss: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.textSize) private var textSize

    var body: some View {
        HStack(spacing: Self.spacing) {
            Text(text.message)
                .font(Toast.font)
                .foregroundStyle(.white)
                .lineLimit(1)
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
        .padding(.leading, Self.leading)
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
