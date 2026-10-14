import AppKit
import Carbon.HIToolbox
import ShotCore
import SwiftUI

@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?
    private static var duration: Duration?
    private static var undoable: PendingAction?
    private static var shown: ToastText?
    private static var actionTitle: String?
    fileprivate static let font = ScaledFont.scaled(13, weight: .bold)
    private static let shadow: CGFloat = 4

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
            ToastView.Action(title: String(localized: "Undo")) { undoable.undo(); hide() }
        } else if let cancel {
            ToastView.Action(title: String(localized: "Cancel"), perform: cancel)
        } else if let reveal {
            ToastView.Action(title: String(localized: "Show")) { NSWorkspace.shared.activateFileViewerSelecting([reveal]); hide() }
        } else {
            nil
        }
        actionTitle = action?.title
        let size = size(of: message, actionTitle: actionTitle)
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

    /// Shows `message` until the next call, changing the toast's text in place without announcing it, so a percentage
    /// can tick up without VoiceOver reading every step. Does nothing when `message` is already showing.
    static func progress(_ message: LocalizedStringResource) {
        progress(String(localized: message))
    }

    /// Progress whose text is already localized.
    @_disfavoredOverload
    static func progress<S: StringProtocol>(_ message: S) {
        let message = String(message)
        guard let panel, let shown, undoable == nil else {
            show(message, duration: nil)
            return
        }
        guard shown.message != message else {
            return
        }
        shown.message = message
        duration = nil
        hideTask?.cancel()
        let size = size(of: message, actionTitle: actionTitle)
        panel.setFrame(NSRect(x: panel.frame.midX - size.width / 2, y: panel.frame.minY, width: size.width, height: size.height), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private static func size(of message: String, actionTitle: String?) -> NSSize {
        let textSize = Preferences().textSize
        var textWidth = (message as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: font.points(textSize), weight: .bold)]).width.rounded(.up)
        if let actionTitle {
            textWidth += (actionTitle as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: textSize.points(12), weight: .bold)]).width.rounded(.up) + 36
        }
        return NSSize(width: textWidth + 32 + shadow, height: 38 + shadow)
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

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }
}

@MainActor
@Observable
private final class ToastText {
    var message: String

    init(message: String) {
        self.message = message
    }
}

private struct ToastView: View {
    struct Action {
        let title: String
        let perform: () -> Void
    }

    let text: ToastText
    let action: Action?
    let hold: (Bool) -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text.message)
                .font(Toast.font)
                .foregroundStyle(Brutal.ink)
                .lineLimit(1)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(BrutalButtonStyle(compact: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .brutalSurface(Color.white.opacity(0.75), glass: true, radius: Brutal.Radius.panel, shadow: 4)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .environment(\.colorScheme, .light)
        .contentShape(Rectangle())
        .onHover(perform: hold)
        .onTapGesture(perform: dismiss)
    }
}
